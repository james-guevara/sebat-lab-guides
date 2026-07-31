# SLURM on Expanse

Job submission templates and tips for SDSC Expanse.

## Quick Test

New to the cluster? Run this first — it grabs a 1-hour interactive shell on 4 cores
and confirms your account, partition, and allocation all work:

```bash
srun --partition=ind-shared --account=ddp195 --time 01:00:00 \
     --nodes=1 --ntasks-per-node=1 --cpus-per-task 4 \
     --export=ALL --pty /bin/bash
```

If you get a shell prompt on a compute node (`exp-#-##`), you're set. Type `exit` to
release it — don't leave interactive jobs idling, they burn allocation.

If it hangs in `PD` (pending), the partition is busy; if it errors out, check that
`--account=ddp195` is spelled right and that you're on the allocation.

## Required Directives

Every job script needs these:

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=ind-shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=2:00:00
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err

# Your commands here
```

**Always include**: `--account=ddp195`, `--partition=ind-shared`, `--nodes`, `--ntasks-per-node`, `--output`, `--error`

> **Use `ind-shared`, not `shared`.** Our `ddp195` jobs go to the `ind-*` (institutional) partitions. Submitting to `shared` is the most common mistake in this lab.

## Partitions

`ddp195` can submit to **exactly four partitions** — all on the lab's institutional
nodes (`exp-15-*`). Everything below is verified against the live scheduler
(2026-07-31).

| Partition | Max Time | Cores/job | Max Mem/job | Use Case |
|-----------|----------|-----------|-------------|----------|
| `ind-shared` | 2 days | 127 (1 node) | 249325M (~243G) | **Default for most jobs** - you share the node |
| `ind-compute` | 2 days | 2048 (16 nodes) | full node (~251G/node) | Full-node parallel jobs |
| `ind-gpu-shared` | 2 days | 160, 16 GPUs | 376832M (~368G) | GPU jobs (partial node) |
| `ind-gpu` | 2 days | 80 (2 nodes), 8 GPUs | full node | Multi-GPU, whole nodes |

Node specs: `ind-shared`/`ind-compute` = 128 cores, 257400M. `ind-gpu*` = 40 cores, 385500M.

### Partitions you CANNOT use

Submitting to any of these fails with `Project not found allocation failure`:

`shared` &nbsp; `compute` &nbsp; `gpu` &nbsp; `gpu-shared` &nbsp; `large-shared` &nbsp; `debug` &nbsp; `preempt`

Note that `shared` is the cluster **default** partition — so if you forget
`--partition`, your job is rejected. Always set it explicitly.

There is no `ind-large-shared`; the lab has no access to the 2TB `large-shared` nodes.
Your memory ceiling is **249325M on `ind-shared`**. Request more and you get
`Requested node configuration is not available`.

## Common Templates

### Basic single-core job

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=ind-shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=1:00:00
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err

python my_script.py
```

### Multi-threaded job (e.g., bcftools, samtools)

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=ind-shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=4:00:00
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err

# Tools use $SLURM_CPUS_PER_TASK threads
bcftools view -@ $SLURM_CPUS_PER_TASK input.vcf.gz -o output.vcf.gz
```

### High-memory job

We have no `large-shared` access, so the most memory you can get is one full
`ind-shared` node: `--mem=249325M`. Use `M` units, not `G` — `--mem=243G` is
248832M and fits, but `--mem=244G` silently exceeds the cap.

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=ind-shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=249325M
#SBATCH --time=8:00:00
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err

# For memory-intensive tools like GATK GenotypeGVCFs
gatk GenotypeGVCFs ...
```

If your job genuinely needs more than 243G, it needs restructuring (shard by
chromosome or region) — there is no partition in our allocation that will run it.

### Array job (process many files)

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=ind-shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=2:00:00
#SBATCH --array=1-100
#SBATCH --output=logs/job_%A_%a.out
#SBATCH --error=logs/job_%A_%a.err

# Get file from list
FILE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" file_list.txt)

# Process it
python process.py $FILE
```

### GPU job

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=ind-gpu-shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --gpus=1
#SBATCH --mem=32G
#SBATCH --time=4:00:00
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err

module load gpu
python train_model.py
```

You **must** request at least one GPU on the `ind-gpu*` partitions. Omitting
`--gpus` fails with `QOSMinGRES allocation failure`, which is an unhelpful way of
saying "you forgot `--gpus=1`".

## Quick Commands

```bash
# Submit job
sbatch job.sh

# Check your jobs
squeue -u $USER

# Cancel job - ALWAYS by explicit job ID
scancel <job_id>

# Job info after completion
sacct -j <job_id> --format=JobID,Elapsed,MaxRSS,State

# Interactive session (1 hour, 4 CPUs)
srun --account=ddp195 --partition=ind-shared --nodes=1 --ntasks-per-node=1 \
     --cpus-per-task=4 --time=01:00:00 --export=ALL --pty /bin/bash
```

## Tips

### Never cancel jobs by filter

`scancel` accepts filters like `-u <user>` and `-n <name>`. Don't use them. They
match more than you expect — interactive sessions, someone else's array job you
inherited, a pipeline that's 20 hours in — and there is no undo and no confirmation
prompt.

```bash
scancel 52832213        # good: one explicit job ID
scancel -u $USER        # NO: kills every job you have, including interactive shells
scancel -n bash         # NO: matches every interactive session by that name
```

Check first with `squeue -u $USER`, then cancel the specific IDs you meant.

### Dry-run a job before you queue it

`--test-only` validates account, partition, and resource limits and reports when the
job *would* start. Nothing is submitted, nothing is charged:

```bash
sbatch --test-only --account=ddp195 --partition=ind-shared \
       --nodes=1 --ntasks-per-node=1 --cpus-per-task=4 --mem=16G \
       --time=01:00:00 --wrap="hostname"
# sbatch: Job 12345678 to start at 2026-07-31T14:29:56 using 4 processors
#         on nodes exp-15-36 in partition ind-shared
```

Any other output is an error worth reading before you burn a real submission. Works
on a script too: `sbatch --test-only job.sh`.

### Use variables for thread count

```bash
# Instead of hardcoding threads:
bcftools view -@ 8 ...

# Use the SLURM variable:
bcftools view -@ $SLURM_CPUS_PER_TASK ...
```

### Create output directories first

```bash
mkdir -p logs
sbatch --array=1-100 job.sh
```

### Check resource usage

After a job completes:
```bash
sacct -j <job_id> --format=JobID,Elapsed,MaxRSS,MaxVMSize,State
```

Use this to tune future job requests.

### Sbatch wrap for quick jobs

```bash
sbatch --account=ddp195 --partition=ind-shared --nodes=1 --ntasks-per-node=1 \
       --cpus-per-task=4 --mem=16G --time=1:00:00 \
       --wrap="python my_script.py"
```
