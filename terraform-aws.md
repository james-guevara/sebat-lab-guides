# Terraform for AWS

Terraform turns AWS infrastructure into reviewed, repeatable configuration. It is useful
for Batch because a working environment spans several connected resources: IAM roles,
launch templates, compute environments, job queues, job definitions, networking, and
sometimes FSx. Reconstructing those settings by clicking through the AWS console is slow
and difficult to audit.

This is a public guide. Names such as `<project>`, `<region>` and `<state-bucket>` are
placeholders. Keep real account IDs, network IDs, state files, controlled-data locations,
and environment-specific values in a private infrastructure repository.

## Why use it

- The intended infrastructure is visible in code.
- `terraform plan` shows a proposed change before it happens.
- Git records why a setting changed.
- Development and production can use the same modules with different private inputs.
- Temporary infrastructure can be removed deliberately when an experiment ends.
- A person or AI agent can inspect the complete design instead of reconstructing it from
  console screenshots.

Terraform does not make a change safe by itself. A reviewed plan, protected state, small
smoke tests, and explicit cleanup are still required.

## What belongs where

```text
Public guide or example                 Private infrastructure repository
------------------------------------    ---------------------------------------
Generic architecture                    Real account, VPC and subnet IDs
Reusable module interfaces              Real IAM policies and trusted principals
Placeholder examples                    Backend and environment configuration
terraform.tfvars.example                terraform.tfvars
Validation workflow                     Terraform state and saved plan files
```

Never commit credentials, `terraform.tfvars`, state, saved plans, or controlled-data
locations. At minimum:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
*.tfplan
crash.log
```

Commit `.terraform.lock.hcl`; it pins provider versions. Commit a sanitized
`terraform.tfvars.example` so another user knows which values are required.

## A maintainable layout

```text
infrastructure/
├── versions.tf
├── providers.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── terraform.tfvars.example
├── modules/
│   ├── batch/
│   └── fsx/
└── environments/
    ├── development/
    └── production/
```

Keep policy decisions near their resources. For example, the Batch module should expose
allowed instance families, maximum vCPUs, Spot versus On-Demand, disk size, and job role
as inputs rather than burying them in several files.

## Remote state

State can contain infrastructure identifiers and sometimes sensitive values. Store it in
a private, encrypted S3 bucket with versioning and narrowly scoped access. Enable state
locking using the backend mechanism supported by the Terraform version in use.

```hcl
terraform {
  # Pin this to the version tested by your infrastructure repository.
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "<state-bucket>"
    key          = "<project>/development/terraform.tfstate"
    region       = "<region>"
    encrypt      = true
    use_lockfile = true
  }
}
```

The backend bucket should normally be created and protected separately. Do not let
destroying an experimental environment delete its own state history.

## Batch resources to model

A practical Batch deployment usually includes:

1. A launch template defining worker disk and bootstrap behavior.
2. An ECS instance role for Batch workers.
3. A job role granting containers only the S3, logs, secrets, and FSx access they need.
4. One or more compute environments.
5. Job queues connected to those environments.
6. Job definitions pinned to container image digests.
7. Log groups with a retention period.

Separate queues are useful when the failure and cost models differ:

```text
Short parallel tasks  -> Spot compute environment
Long barrier/merge    -> On-Demand compute environment
Large local staging   -> workers with larger encrypted EBS volumes
Repeated shared reads -> FSx-enabled compute environment
```

Avoid embedding pipeline parameters in Terraform. Terraform should provision the place
where work runs; Nextflow or the pipeline runbook should define the scientific workflow.

## The normal workflow

Run these from a stable checkout and a named, non-admin AWS profile:

```bash
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=change.tfplan
terraform show change.tfplan
terraform apply change.tfplan
terraform output
```

Before applying, read the summary and inspect every replacement or deletion. A change to
a launch template may be harmless; replacement of a filesystem or compute environment
may interrupt work or delete data.

After applying:

```bash
aws batch describe-compute-environments --compute-environments <name>
aws batch describe-job-queues --job-queues <name>
```

Submit one small smoke job and verify its output contents before increasing array size or
`maxvCpus`. Infrastructure that reaches `VALID` has not yet demonstrated that its jobs
can pull the image, read data, write results, or mount storage.

## Changes and cleanup

Before changing or destroying infrastructure:

1. Check for running and queued Batch jobs.
2. Copy durable results from worker disks or FSx to S3.
3. Produce object-count, byte-count, and checksum manifests where appropriate.
4. Run `terraform plan` and resolve the exact deletion targets.
5. Preserve the final plan and relevant run metadata in the private project record.

Then, for an environment intended to be temporary:

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
```

Do not teach an AI agent to run `terraform destroy` automatically. It should identify
the environment, show the proposed targets, verify backups, and request confirmation.

## Small CI/CD pipeline

Keep continuous integration (CI) separate from deployment (CD). CI should reject
malformed infrastructure and code without changing AWS. CD begins only after review and
explicit approval. A useful workflow is:

```text
Pull request
    -> Markdown and shell checks
    -> Python tests
    -> Nextflow syntax/config check
    -> terraform fmt + validate
    -> read-only terraform plan for an approved environment
CI ends; human review and approval
    -> approved apply (CD)
    -> one small Batch smoke test
```

A minimal GitHub Actions validation job can run without AWS credentials if it only checks
format and module syntax:

```yaml
name: validate

on:
  pull_request:

permissions:
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform fmt -check -recursive
      - run: terraform init -backend=false
      - run: terraform validate
```

If CI needs AWS access, prefer short-lived OpenID Connect credentials and a narrowly
scoped read-only planning role. Do not store long-lived AWS keys as repository secrets.
Production `apply` should require an approved environment or an equivalent human gate.

Container CI should build once, test that exact image, push it to ECR, and record its
digest. Batch job definitions should use the digest rather than a mutable tag.

## Runnable example

The sanitized example in [`examples/aws-batch-terraform/`](examples/aws-batch-terraform/)
creates a small Spot-backed development compute environment, queue, launch template, and
hello-world job definition. It expects an existing VPC subnet and security group; creating
the lab network is intentionally outside the public example.

The example is a teaching scaffold, not a production environment. Review its IAM,
instance families, quotas, logging, image, storage, and network path before adapting it.

## Giving an AI agent this guide

Provide the private runbook separately and state the permitted scope. A useful request is:

> Read the public Terraform guide and the private development-environment runbook. Start
> with read-only inspection. Do not apply, destroy, change IAM, launch a large Batch
> array, or delete data without showing the exact plan and receiving approval. Use a
> one-job smoke test and verify output content before scaling.

## See also

- [AWS for the Lab](aws-setup.md) — credentials, roles, ECR, and cost guardrails
- [Nextflow on AWS Batch](nextflow-aws-batch.md) — workflow behavior on Batch
- [FSx for Lustre with Batch](fsx-aws.md) — shared storage and its lifecycle
- [Moving Data in AWS](data-movement-aws.md) — staging, verification, and egress
