# Claude Code on Clusters

Installing and using Claude Code on HPC clusters like Expanse.

## Installation

SSH to the cluster and run:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

This installs to `~/.local/bin/claude`. Add to your PATH if needed:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Authentication

Clusters don't have browsers, so use API key authentication:

### Option 1: Anthropic Console (recommended)

1. Go to https://console.anthropic.com
2. Create an account or log in
3. Generate an API key
4. On the cluster:
   ```bash
   claude login --console
   ```

### Option 2: Claude.ai Account (Pro/Max subscribers)

If you have Claude Pro or Max:

```bash
claude login
```

This starts an OAuth flow. You'll get a URL to visit - open it on your laptop, authenticate, and it will work.

## Usage on Clusters

### Interactive mode

```bash
claude
```

Then chat normally. Use `/help` for commands.

### Non-interactive mode (for scripts/batch jobs)

```bash
claude -p "Your prompt here"
```

With specific tools allowed:

```bash
claude -p "Analyze the VCF files in this directory" --allowedTools "Read,Grep,Bash"
```

### In SLURM jobs

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=1:00:00
#SBATCH --output=claude_%j.out

claude -p "Summarize the results in results.txt" --allowedTools "Read"
```

## Using with SSH Multiplexing

If you're running Claude Code on your **local machine** and want it to SSH to the cluster:

1. Set up SSH multiplexing (see [ssh-config.md](ssh-config.md))
2. Manually SSH to expanse in a separate terminal first
3. Now Claude Code can SSH without password prompts

## Tips

### Reduce context usage

Long outputs fill up context fast. Use limits:

```bash
# In your prompts
"Show me the first 50 lines of the error log"

# Or pipe through head
cat large_file.txt | head -100
```

### Session persistence

Claude Code sessions can be resumed:

```bash
# Get session ID from previous run
claude -p "Continue analysis" --resume SESSION_ID
```

### Configuration

Settings are stored in `~/.claude/`. You can create a `CLAUDE.md` file there with persistent instructions:

```bash
# Example ~/.claude/CLAUDE.md
# Cluster-specific instructions

I'm working on Expanse (SDSC cluster).
- SLURM account: ddp195
- Project directory: /expanse/projects/sebat1/USERNAME/
- Use micromamba for Python environments
```

## Troubleshooting

### "command not found: claude"

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add to `~/.bashrc` to make permanent.

### Authentication errors

```bash
# Re-authenticate
claude logout
claude login --console
```

### Rate limits

If you hit rate limits, wait a few minutes or check your API plan limits.
