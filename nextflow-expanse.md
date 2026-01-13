# Nextflow on Expanse

Running Nextflow pipelines on SDSC Expanse.

## Setup

### 1. Create a micromamba environment

```bash
# Install micromamba if you don't have it
"${SHELL}" <(curl -L micro.mamba.pm/install.sh)

# Create environment with Nextflow
micromamba create -n nf_env nextflow -c bioconda -c conda-forge
```

### 2. Fix NFS lock file issue

Expanse's NFS doesn't handle lock files well:

```bash
micromamba config set use_lockfiles False
```

### 3. Set temp directory

```bash
# Add to ~/.bashrc or ~/.zshrc
export NXF_TEMP=/expanse/projects/sebat1/$USER/nextflow_temp
mkdir -p $NXF_TEMP
```

## Running Pipelines

### Interactive (for testing)

```bash
# Get an interactive session first
srun --account=ddp195 --partition=shared --nodes=1 --ntasks-per-node=1 \
     --cpus-per-task=4 --mem=16G --time=2:00:00 --pty bash

# Activate environment and run
micromamba activate nf_env
nextflow run pipeline.nf -c config.nf
```

### Via sbatch (for production)

```bash
sbatch --account=ddp195 --partition=shared --nodes=1 --ntasks-per-node=1 \
       --cpus-per-task=4 --mem=16G --time=24:00:00 \
       --output=nf_%j.out --error=nf_%j.err \
       --wrap='eval "$(micromamba shell hook --shell bash)" && micromamba activate nf_env && nextflow run pipeline.nf -c config.nf'
```

## Resume and Caching

### IMPORTANT: Don't edit module files when planning to resume

Editing `modules/*.nf` files invalidates the cache. All tasks restart from scratch.

**Wrong (breaks cache):**
```groovy
// In modules/my_process.nf
process MY_PROCESS {
    memory '32 GB'  // Changing this invalidates cache!
}
```

**Correct (preserves cache):**
```groovy
// In nextflow.config
process {
    withName: 'MY_PROCESS' {
        memory = '32 GB'
    }
}
```

### Resume a failed run

```bash
nextflow run pipeline.nf -resume
```

### Lock file errors on resume

If resume fails with a lock error:

```bash
# Find the stale process
lsof /path/to/.nextflow/cache/SESSION_ID/db/LOCK

# Kill it
kill <PID>

# Try resume again
nextflow run pipeline.nf -resume
```

## Example Config for Expanse

```groovy
// nextflow.config
process {
    executor = 'slurm'
    queue = 'shared'
    clusterOptions = '--account=ddp195'

    // Default resources
    cpus = 4
    memory = '16 GB'
    time = '4h'

    // Override for specific processes
    withName: 'HEAVY_PROCESS' {
        cpus = 16
        memory = '64 GB'
        time = '24h'
    }
}

// Singularity for containers
singularity {
    enabled = true
    autoMounts = true
    cacheDir = '/expanse/projects/sebat1/$USER/singularity_cache'
}

// Trace and reports
trace {
    enabled = true
    file = 'trace.txt'
}

report {
    enabled = true
    file = 'report.html'
}
```

## Running Subworkflows Separately

Use `-entry` to run specific subworkflows:

```bash
nextflow run main.nf -entry RUN_VCF_PROCESSING -c config.nf
```

Use `--trace_prefix` to identify which subworkflow generated the trace:

```bash
nextflow run main.nf -entry RUN_VCF_PROCESSING --trace_prefix 'vcf_' -c config.nf
```

## Useful Commands

```bash
# View running Nextflow processes
ps aux | grep nextflow

# Clean up work directory (careful!)
nextflow clean -f

# View execution report
open report.html

# Check trace for bottlenecks
cat trace.txt | column -t -s $'\t' | less -S
```

## Common Issues

### "No such file" errors

- Check that input files exist and paths are absolute
- Ensure Singularity can access the paths (check `autoMounts`)

### Out of memory

- Check `trace.txt` for actual memory usage
- Increase memory in config (not in module files!)

### Jobs stuck in queue

- Check cluster status: `squeue -u $USER`
- Try smaller resource requests
- Check if you hit allocation limits
