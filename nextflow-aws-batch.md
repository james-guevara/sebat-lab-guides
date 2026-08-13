# Nextflow on AWS Batch

Porting a Nextflow pipeline from SLURM to AWS Batch. The executor swap is one line; the
six things below are what actually take the time, and most of them fail *silently* or
with an error that points somewhere else.

Assumes you've read [AWS for the Lab](aws-setup.md) for profiles, roles, ECR and cost
guardrails. Placeholders like `<ACCOUNT_ID>` and `<work-bucket>` need your real values.

## The short version

| SLURM assumption | On Batch |
|---|---|
| Shared filesystem everywhere | **None.** Anything a task reads must be staged or in the image |
| `module load foo` | No modules. Every tool comes from the container |
| Ask for a node (`cpus = 192`) | Ask for **resources**; Batch chooses the instance. Scale out, not up |
| `nproc` / `free` describe my allocation | They describe the **host**. Trust the cgroup instead |
| `beforeScript` sets up my task env | It runs on the **host**, before `docker run` — never reaches the task |
| Big input files are just *there* | They're **copied** to local disk. Check the disk is big enough |
| A job that exits 0 did the work | Verify outputs have **rows**, not just that files exist |

## 1. Mental model

Batch is a queue plus an autoscaling pool. You submit a job saying "I need 8 vCPUs and
32 GB and this container image"; Batch launches or reuses an instance that fits, runs the
container, and tears it down. Nextflow's `awsbatch` executor does this per task, staging
inputs from S3 and copying outputs back.

Consequences that matter for a ported pipeline:

- **The work directory must be on S3** (`workDir = 's3://<work-bucket>/nextflow/'`). Tasks
  have no shared mount, so S3 is how stages hand off.
- **Containers are mandatory**, not optional as they are on a cluster with modules.
- **Parallelism comes from more jobs**, not bigger ones. A 22-chromosome pipeline wants 22
  concurrent jobs of 8 cpus, not one job of 176.

## 2. Add a site config; don't edit the pipeline

If the pipeline separates site configuration (many do — `setup/<site>/<site>.config`,
profiles, or similar), add a new one rather than editing shared files. Then upstream
changes still merge.

```groovy
// setup/aws/aws.config
docker.enabled    = true
docker.autoMounts = true

aws {
    region = '<region>'
    batch {
        jobRole              = 'arn:aws:iam::<ACCOUNT_ID>:role/<JobRole>'
        maxParallelTransfers = 8
        maxTransferAttempts  = 3
        delayBetweenAttempts = '30 sec'
    }
}

workDir = 's3://<work-bucket>/nextflow/'

process {
    executor  = 'awsbatch'
    queue     = '<job-queue>'
    container = '<ACCOUNT_ID>.dkr.ecr.<region>.amazonaws.com/<image>@sha256:<digest>'
}
```

Check what it resolves to before running anything — a config that silently fails to load
looks identical to one that loaded and did nothing:

```bash
mkdir /tmp/cfgtest && cd /tmp/cfgtest
echo 'includeConfig "/path/to/aws.config"' > nextflow.config
nextflow config          # prints the effective configuration
```

Also check `~/.nextflow/config` on the head node. Global settings merge into every run,
so a stale `fusion`/`wave` block or a duplicate `executor` from months ago will apply to
your run without appearing in your config file.

## 3. The cgroup trap: scripts that size themselves get OOM-killed

This is the one that cost the most time. Cluster scripts commonly do:

```bash
cpus="${SLURM_CPUS_ON_NODE:-$(nproc)}"
# and, if SLURM_MEM_PER_NODE is unset:
plink_mem=$(( available_mem * 90 / 100 ))      # from `free -m`
```

Under SLURM those variables exist and everything is sized correctly. In a container they
don't, so the fallback runs — and **`nproc` and `free` report the host machine, not the
container's cgroup limit**. A task allocated 4 cpus and 12 GB on a 16-core/64 GB instance
tells the tool to use 16 threads and ~57 GB. The tool obliges, exceeds the cgroup, and the
kernel kills it:

```
pVCF_to_plinkNF.sh: line 68: 13 Killed   plink2 --vcf ... --memory 27322 ...
```

Note what that looks like from the outside: a bare `Killed`, no stack trace, and a memory
number *larger than the task asked for*. It gets worse on bigger instances, so it looks
like flakiness.

**The fix that doesn't work:** injecting the variables from Nextflow.

```groovy
// DOESN'T WORK — beforeScript runs in the host wrapper, before `docker run`
beforeScript = { "export SLURM_CPUS_ON_NODE=${task.cpus}" }
```

The exports land in `.command.run` on the host and never enter the container. You can
confirm this the same way we did: the variable is present in `.command.run` while
`.command.log` shows the script using host values.

**The fix that does work:** have the container read its own cgroup. `BASH_ENV` is sourced
by every non-interactive bash, which is exactly how Nextflow invokes `.command.sh`
(`/etc/profile.d` is not — that's login shells only).

```dockerfile
COPY cgroup_env.sh /opt/bin/cgroup_env.sh
ENV BASH_ENV=/opt/bin/cgroup_env.sh
```

```bash
# cgroup_env.sh — set only if unset, so a real SLURM allocation still wins
if [ -z "${SLURM_CPUS_ON_NODE:-}" ] || [ -z "${SLURM_MEM_PER_NODE:-}" ]; then
    if [ -r /sys/fs/cgroup/cpu.max ]; then                     # cgroup v2
        read -r _q _p < /sys/fs/cgroup/cpu.max
        [ "$_q" != "max" ] && export SLURM_CPUS_ON_NODE=$(( (_q + _p - 1) / _p ))
    fi
    if [ -r /sys/fs/cgroup/memory.max ]; then
        _m=$(cat /sys/fs/cgroup/memory.max)
        [ "$_m" != "max" ] && export SLURM_MEM_PER_NODE=$(( _m / 1024 / 1024 ))
    fi
    # add /sys/fs/cgroup/cpu/cpu.cfs_quota_us + memory/memory.limit_in_bytes for v1
fi
```

Verify it directly rather than trusting it:

```bash
docker run --rm --cpus=3 --memory=6g <image> bash -c 'echo $SLURM_CPUS_ON_NODE $SLURM_MEM_PER_NODE'
# 3 6144        (while nproc still says 8)
```

**But that test is misleading, and this is the part that bit us.** `--cpus` sets a hard
CPU *quota*, so `cpu.max` exists and the snippet above works. **Neither Nextflow's local
executor nor AWS Batch sets a quota** — both use relative CPU *shares*. So `cpu.max` reads
`max`, the CPU branch never fires, and you are back to `nproc`:

```
# a task requesting 4 cpus / 16 GB, on Batch:
PLINK memory: 14745 MB     <- correct: 90% of 16 GB, memory branch worked
Running with 48 cores      <- wrong: the HOST's core count
```

Memory works everywhere (both set a hard memory limit); CPU needs a second source. Under
Batch, the ECS task metadata endpoint is authoritative:

```bash
if [ -z "$_cpus" ] && [ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]; then
    _cpus=$(curl -fsS --max-time 2 "$ECS_CONTAINER_METADATA_URI_V4" \
            | python3 -c 'import json,sys; c=(json.load(sys.stdin).get("Limits") or {}).get("CPU")
print(max(1, round(c/1024) if c and c>=64 else round(c)) if c else "")')
fi
```

Do **not** try to back-compute vCPUs from `cpu.shares`/`cpu.weight`. We tried: Docker's
shares→weight mapping isn't the documented runc formula, `--cpu-shares=2048` came back as
4 cpus, and worst of all an *unconstrained* container reported 3 cpus because the default
`cpu.weight` is 100. A shim that invents a limit is more dangerous than no shim — fall
through to `nproc` and be honestly wrong instead.

Why the CPU half matters as much as memory: scripts that do `parallel -j $cpus` will
launch one job per **host** core inside a small container — 48 concurrent bcftools in a
4-cpu/8 GB task.

## 4. Absolute script paths break

Processes that shell out to a path on the shared filesystem fail immediately, because
there is no shared filesystem:

```groovy
script:
"""
bash ${params.scriptDir}/do_thing.sh ${input}      // /project/lab/scripts/... — not in the container
"""
```

Three options, in order of how little you have to touch their code:

1. **Bake the scripts into the image** and point `params.scriptDir` at the in-image path
   (`/opt/<pipeline>/scripts`). Zero edits upstream. Cost: rebuild the image when scripts
   change — fine for reproducing a fixed version, annoying while actively editing.
   Remember any data files the scripts read (BED files, HMM models) too.
2. **Move them to `bin/`** in the project root. Nextflow stages `bin/` automatically and
   puts it on `PATH`. Requires editing the processes.
3. **Declare them as process inputs** so Nextflow stages them per task. Most explicit,
   most edits.

## 5. Resources: translate, don't copy

Cluster configs are written for whole nodes and don't carry over:

```groovy
withName: callBatchCNVs { cpus = 192 }                  // a SLURM node
withName: generate_pfb  { cpus = 64; memory = '250 GB' } // ditto
```

No single instance in a typical compute environment provides that, so the job sits
`RUNNABLE` forever — which looks like a stuck queue, not a config error. Re-express as
something schedulable (8–16 cpus, tens of GB) and let concurrency do the work.

Two related traps:

- **`maxvCpus` on the compute environment caps everything.** At 256, you get ~256
  single-core tasks at once no matter what you submit.
- **Check the local executor's limits too** when smoke-testing: a `memory = '32 GB'`
  default against a 28 GB box fails with `Process requirement exceeds available memory`.

## 6. Spot: right for fan-out, wrong for barriers

Spot instances are 60–70% cheaper and ideal for thousands of short parallel tasks — a
reclaim costs one cheap retry. Handle it explicitly:

```groovy
// reclaim arrives as SIGKILL/SIGTERM
errorStrategy = { task.exitStatus in [104, 134, 137, 139, 143] ? 'retry' : 'finish' }
maxRetries    = 2
```

Use `finish`, never `errorStrategy = 'ignore'` globally — ignoring failures produces
silently incomplete results, which is worse than a stopped pipeline.

But spot is a poor fit for **single long barrier jobs** — a merge, or an O(N²) kinship
step, that runs for hours and restarts from zero when reclaimed. Give those an on-demand
queue and route just them to it:

```groovy
withName: plink_filter_merge { queue = '<ondemand-queue>' }
```

A handful of on-demand jobs costs little and removes the worst failure mode.

## 7. Disk: staging copies whole files

Nextflow **copies** each input to the worker's local disk before the task runs. Fine for
1 GB per-sample files; fatal for a 500 GB joint-called VCF against a default 30 GB root
volume. And the tool matters: `bcftools` can stream a region straight from `s3://` via a
`.tbi` index, but **`plink2 --vcf` requires a local path**.

Options: a compute environment with larger volumes; streaming filesystems (Fusion, which
needs a Seqera licence — check before designing around it); or stream through a filter and
write only what's needed locally. If the next step discards everything but biallelic SNPs
above a MAF threshold, filtering during the stream shrinks what hits disk enormously.

Beware assuming a "small region" is cheap when the cohort is wide: a 2 Mb window across
12,519 samples is ~4–6 GB, and re-compressing it is CPU-bound. `--compress-level 1` on
throwaway intermediates is most of the size reduction for a fraction of the time
(uncompressed output is identical either way — only the packing differs).

## 8. Debug locally first

Before touching Batch, run the pipeline with `executor = 'local'` and Docker on the head
node, with small inputs. That separates "do the scripts and container work" from "does
Batch work", and the feedback loop is minutes instead of tens of minutes. Traps 3, 4 and 5
above all reproduce locally.

Then flip the executor. Anything that breaks after that is genuinely Batch-specific:
IAM, queues, S3 staging.

## 9. Exit 0 is not success

Batch and Nextflow report exit status; they can't tell you the output is meaningful.
Pipelines built around shell tools can produce **empty but well-formed** results:

```
LRR_BAF/<SAMPLE_ID>.baf_lrr.tsv      64 bytes    # header row, zero data rows
```

That came from inputs that were never staged (see the next section): the paths inside the
container pointed at files that didn't exist, `bcftools` opened nothing, and the wrapper
wrote a header and exited 0. Every stage "succeeded".

(Our first hypothesis was a chromosome-naming mismatch — `21` in the `.bim` vs `chr21` in
the VCF. It was wrong: the tool normalised names itself. Worth stating because it is the
plausible-looking explanation you will reach for first; check the task's `.command.log`
for what the tool actually said before theorising.)

So check the content, every time:

```bash
wc -l results/*.tsv          # rows, not just existence
head -3 results/*.tsv
```

and prefer `set -euo pipefail` plus explicit row-count assertions in any wrapper you
write yourself.

## 10. Stage files, not paths

The single most productive bug class in our port, and it is silent every time. Pipelines
written for a shared filesystem pass **paths** and let the tool open them. That works when
every node sees the same disk. In a container it does not, and nothing errors — the tool
just finds nothing.

Two shapes of it, both from the same pipeline:

```groovy
// (a) file paths written into a text file, only the text file is an input
.map { vcf -> "${sid}\t${vcf.toAbsolutePath()}" }     // container: no such path
// (b) a directory passed as a string
input: tuple path(batch), val(baf_dir)                // baf_dir = "s3://.../LRR_BAF"
```

Fix both by declaring real inputs so Nextflow stages the data:

```groovy
input: tuple val(sids), path(gvcfs), path(gvcf_idxs)  // (a) — and don't forget indexes
input: tuple path(batch), path("baf_all/*")           // (b)
```

Indexes deserve their own mention: passing paths as strings hides the fact that `.tbi`
files were never staged either, and `bcftools -R` needs them.

**Two related traps:**

**String interpolation drops the filesystem scheme.** This works locally and fails on S3:

```groovy
def tbi = file("${vcf}.tbi")            // s3://bucket/key -> /bucket/key  (a LOCAL path)
def tbi = vcf.resolveSibling("${vcf.name}.tbi")   // correct — stays on S3
```
Never build one path from another by string surgery; use `resolve`, `resolveSibling`,
`getParent`, `getName`.

**Batch sizes tuned for a shared filesystem are catastrophic when inputs are copied.**
Upstream batched 125 samples per job — free when files are merely referenced. On Batch
that means staging ~125 GB into one container. Even 20 died with
`[Errno 12] Cannot allocate memory` during staging. On object storage, prefer **one sample
per task**: staging cost scales with batch size, per-task retry gets finer, and a spot
reclaim loses one sample instead of twenty.

## 11. Smaller things that cost an hour each

- **A job asking for an instance's *full* memory never schedules.** 64 GB only fits a
  64 GB instance, but the ECS agent and OS reserve some, so it fits nowhere: the job sits
  `RUNNABLE` forever, the compute environment stays at 0 vCPUs, and **Batch reports no
  error at all**. Size to ~90% of the target instance. Diagnose with
  `aws batch describe-jobs --jobs <id>` and compare `resourceRequirements` to reality.
- **Use one `withName` selector per process.** A regex `withName: 'foo.*'` and an exact
  `withName: 'foo'` both match, and the regex won for us regardless of declaration order —
  so the block we thought was in effect was silently ignored.
- **`publishDir mode: 'link'` doesn't work on S3.** Nextflow warns and falls back to
  `copy`, which duplicates every published file. Set the mode explicitly.
- **Nextflow's AWS Batch executor needs the AWS CLI *inside* the task container** — it
  shells out to `aws s3 cp` to stage. Images that lack it fail before your code runs.
- **`-resume` is opt-in, and the cache lives in the launch directory.** A fresh launch
  directory means no cache even with `-resume`. The task hash includes script text,
  inputs, *and the container image* — so bumping an image tag legitimately re-runs
  everything. Iterate from one stable launch dir.

## See also

- [AWS for the Lab](aws-setup.md) — profiles, roles, ECR, cost guardrails
- [Nextflow on Expanse](nextflow-expanse.md) — the SLURM equivalent
- [Working Habits](working-habits.md) — on verifying rather than assuming
