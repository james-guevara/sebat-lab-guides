# Containers on Expanse

Using Singularity/Apptainer containers on SDSC Expanse, and the four things that
waste a day if you don't know them up front.

## The short version

| You want to | Do this |
|---|---|
| Get an existing image | `singularity pull` — **as a batch job**, not on a login node |
| Build your own image | **Not on Expanse.** Build it elsewhere (CI) and pull the result |
| Use it with Nextflow | Make sure the image contains `procps`, or every task fails |

## 1. You cannot build images on Expanse

```
$ singularity build --fakeroot my.sif my.def
FATAL: could not use fakeroot: no mapping entry found in /etc/subuid for <user>
```

`--fakeroot` needs a user-namespace mapping in `/etc/subuid`. Expanse doesn't create
one for user accounts, so unprivileged def-file builds are impossible. The `--fakeroot`
flag exists in the help text, which makes this look like a usage error rather than a
policy one.

There's no local workaround: `%post` needs root-equivalent privileges to install
packages, and you don't have them.

**What to do instead:** build the image somewhere that does have Docker and root, push
it to a registry, and pull it here. Options in rough order of convenience:

- **GitHub Actions → GHCR.** A workflow in the repo builds the image on GitHub's
  runners and publishes it. Free, no extra accounts, and the image ends up versioned
  alongside the code that needs it — so changing a pinned dependency is a reviewable
  commit rather than someone quietly editing a shared conda env.
- **Your own machine**, if Docker works there. Note Apple Silicon builds `arm64` by
  default and Expanse is `x86_64`, so you need `docker buildx --platform linux/amd64`.
- **Sylabs remote builder** (`singularity remote login`, then `singularity build --remote`).
  A remote endpoint is already configured; it needs a cloud.sylabs.io account.

## 2. `singularity pull` must run as a job

On a login node:

```
FATAL ERROR: Failed to create thread
FATAL ERROR: Out of memory (frag_thrd)
```

That's `mksquashfs`, which `singularity pull` shells out to, hitting login-node memory
limits. It is not a permissions or network problem, and the message doesn't mention
memory limits or squashfs in a way that makes the cause obvious.

It works fine in a job:

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=ind-shared
#SBATCH --nodes=1 --ntasks-per-node=1 --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=1:00:00
#SBATCH --output=pull_%j.out
#SBATCH --error=pull_%j.err
set -euo pipefail
module load singularitypro/4.1.2

# Node-local /tmp is the RIGHT choice here. The usual "never use /tmp on Expanse"
# rule is about /tmp not being shared between login and compute nodes; a pull is
# self-contained within one job, and NFS would be much slower.
export SINGULARITY_CACHEDIR=/tmp/sc_$SLURM_JOB_ID
export SINGULARITY_TMPDIR=/tmp/st_$SLURM_JOB_ID
mkdir -p "$SINGULARITY_CACHEDIR" "$SINGULARITY_TMPDIR"

singularity pull --force /path/to/shared/space/my.sif docker://ghcr.io/owner/image:tag

rm -rf "$SINGULARITY_CACHEDIR" "$SINGULARITY_TMPDIR"
```

Put the `.sif` in project space (`/expanse/projects/sebat1/...`), not your home
directory, or nobody else can use it.

## 3. Nextflow containers need `procps`

If you build a slim image, every process fails like this:

```
exit status 1
.command.out   (empty)
.command.err   Command 'ps' required by nextflow to collect task metrics cannot be found
```

Nextflow's task wrapper shells out to `ps` for per-task metrics and aborts when it's
missing. Your script never runs, and nothing in the error mentions your code — it
looks like a pipeline bug. `python:*-slim`, `alpine` and most minimal bases omit it.

```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends procps \
 && rm -rf /var/lib/apt/lists/*
```

Worth asserting it at build time so a later base-image change can't reintroduce it:

```dockerfile
RUN command -v ps >/dev/null || { echo "procps missing — Nextflow needs ps"; exit 1; }
```

## 4. BLAS-linked tools need their thread count capped

Some containers (bcftools builds linked against OpenBLAS, for one) size per-thread
buffers from the host's core count. On a many-core login node that overshoots:

```
OpenBLAS error: Memory allocation still failed after 10 retries, giving up.
```

Pass the limit through into the container:

```bash
export SINGULARITYENV_OPENBLAS_NUM_THREADS=1
export SINGULARITYENV_OMP_NUM_THREADS=1
```

## Using containers in Nextflow

```groovy
singularity {
    enabled = true
    autoMounts = true
    runOptions = '-B /expanse/projects/sebat1'   // bind project space
}

process {
    withName: 'MY_PROCESS' {
        container = '/expanse/projects/sebat1/.../containers/my.sif'
    }
}
```

Two things to know:

**A process with no `container` directive runs on the host**, even with
`singularity.enabled = true`. That's easy to miss and means a pipeline can look
containerized while quietly depending on host tools — the usual symptom being
`command not found` for something like `tabix` on one node but not another.

**Never point a container param at a path in someone's home directory.** The same
applies to conda/micromamba envs: an env at `/home/<user>/micromamba/envs/foo` means
only that user can run the pipeline. Project space or a container, nothing else.

## Pinning versions

Pin to what you have working, not to `latest`, and record the pins in the image
definition rather than in a shared env. Libraries with fast-moving APIs will silently
change behaviour otherwise. It's also worth asserting in the build that the specific
functions your code calls actually exist — that turns a bad pin into a failed build
instead of a crash two hours into a run.

```dockerfile
RUN python -c "import mylib; assert hasattr(mylib, 'the_function_we_call')"
```

## Checking what you've got

```bash
module load singularitypro/4.1.2

singularity exec my.sif python -c "import duckdb; print(duckdb.__version__)"
singularity exec my.sif which ps            # should print /usr/bin/ps
singularity inspect my.sif                  # labels and metadata
```
