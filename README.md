# Sebat Lab Guides

Guides and templates for working with SDSC clusters (Expanse, TSCC), AWS, and AI coding tools.

## Quick Links

| Guide | Description |
|-------|-------------|
| [SSH Config](ssh-config.md) | SSH multiplexing for SDSC clusters (authenticate once) |
| [SLURM on Expanse](slurm-expanse.md) | Job submission templates and tips |
| [Nextflow on Expanse](nextflow-expanse.md) | Running Nextflow pipelines on the cluster |
| [Globus Setup](globus-expanse.md) | File transfers with Globus CLI |
| [Claude Code on Clusters](claude-code-cluster.md) | Installing and using Claude Code via SSH |

## For Claude Code Users

These guides can be:
1. **Copy-pasted into Claude Code prompts** when you need help with a specific topic
2. **Added to your `~/.claude/CLAUDE.md`** for persistent context across sessions

### Example: Adding to CLAUDE.md

```bash
# Copy a guide to your CLAUDE.md
cat ~/projects/sebat-lab-guides/ssh-config.md >> ~/.claude/CLAUDE.md
```

Or selectively copy sections you need.

## Contributing

Found something useful? Add it here so others benefit too.

## Lab Resources

- **Expanse allocation**: `ddp195` (SLURM account)
- **Project storage**: `/expanse/projects/sebat1/`
- **Lustre scratch**: `/expanse/lustre/projects/ddp195/`
