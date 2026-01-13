# SLURM on Expanse

Job submission templates and tips for SDSC Expanse.

## Required Directives

Every job script needs these:

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=2:00:00
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err

# Your commands here
```

**Always include**: `--account=ddp195`, `--nodes`, `--ntasks-per-node`, `--output`, `--error`

## Partitions

| Partition | Max Time | Max Nodes | Use Case |
|-----------|----------|-----------|----------|
| `shared` | 48 hours | 1 (partial) | Most jobs - you share the node |
| `compute` | 48 hours | 32 | Large parallel jobs needing full nodes |
| `gpu-shared` | 48 hours | 1 | GPU jobs (partial node) |
| `gpu` | 48 hours | 4 | Multi-GPU jobs |
| `large-shared` | 48 hours | 1 | High-memory jobs (up to 2TB RAM) |

## Common Templates

### Basic single-core job

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=shared
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
#SBATCH --partition=shared
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

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=large-shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=256G
#SBATCH --time=8:00:00
#SBATCH --output=job_%j.out
#SBATCH --error=job_%j.err

# For memory-intensive tools like GATK GenotypeGVCFs
gatk GenotypeGVCFs ...
```

### Array job (process many files)

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=shared
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
#SBATCH --partition=gpu-shared
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

## Quick Commands

```bash
# Submit job
sbatch job.sh

# Check your jobs
squeue -u $USER

# Cancel job
scancel <job_id>

# Cancel all your jobs
scancel -u $USER

# Job info after completion
sacct -j <job_id> --format=JobID,Elapsed,MaxRSS,State

# Interactive session (2 hours, 4 CPUs, 16GB)
srun --account=ddp195 --partition=shared --nodes=1 --ntasks-per-node=1 \
     --cpus-per-task=4 --mem=16G --time=2:00:00 --pty bash
```

## Tips

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
sbatch --account=ddp195 --partition=shared --nodes=1 --ntasks-per-node=1 \
       --cpus-per-task=4 --mem=16G --time=1:00:00 \
       --wrap="python my_script.py"
```
