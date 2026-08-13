# Sebat Lab Guides

Guides and templates for working with SDSC clusters (Expanse, TSCC), AWS, and AI coding tools.

## Quick Links

| Guide | Description |
|-------|-------------|
| [SSH Config](ssh-config.md) | SSH multiplexing for SDSC clusters (authenticate once) |
| [SLURM on Expanse](slurm-expanse.md) | Job submission templates and tips |
| [Nextflow on Expanse](nextflow-expanse.md) | Running Nextflow pipelines on the cluster |
| [Globus Setup](globus-expanse.md) | File transfers with Globus CLI |
| [Sharing Data via S3](s3-sharing-expanse.md) | Send data to outside collaborators — presigned links, or a bucket with scoped keys |
| [Containers on Expanse](containers-expanse.md) | Singularity: why you can't build here, pulling as a job, the `procps` trap |
| [Measuring Storage](filesize-expanse.md) | How big is it, what *is* it, what can I delete — quotas, `diskus`, manifests, S3 inventory |
| [AWS for the Lab](aws-setup.md) | Profiles, instance roles, cross-account S3, ECR, and cost guardrails |
| [Nextflow on AWS Batch](nextflow-aws-batch.md) | Porting a SLURM pipeline: the cgroup trap, staging, spot vs on-demand |
| [Claude Code on Clusters](claude-code-cluster.md) | Installing and using Claude Code via SSH |
| [Working Habits](working-habits.md) | One person's opinions on cluster hygiene, verification, and tooling — take or leave |

## Pipeline runbooks

Guides here cover cluster *tooling*. Runbooks for specific pipelines live with the
pipeline, so the commands can't drift from the code:

| Pipeline | Runbook |
|---|---|
| Rare variant (G2MH) | [rare-variant-pipeline/docs/running-g2mh.md](https://github.com/james-guevara/rare-variant-pipeline/blob/main/docs/running-g2mh.md) |

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
