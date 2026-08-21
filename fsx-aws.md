# FSx for Lustre with Batch

Amazon FSx for Lustre provides a shared high-throughput filesystem that EC2 and AWS Batch
workers can mount. It is useful when many jobs repeatedly read the same large inputs. It
is not a replacement for S3: S3 remains the durable home for inputs, outputs, and backups.

This guide describes the pattern, not a live filesystem. Keep filesystem IDs, DNS names,
mount names, network IDs, and controlled-data locations in a private runbook.

## The storage choices

| Situation | Good default |
|---|---|
| Durable inputs, results, and archives | S3 |
| One task reads an object once | Stage from S3 to encrypted local EBS |
| Many tasks repeatedly read the same large objects | FSx for Lustre |
| Temporary intermediate unique to one task | Local EBS |
| Interactive development | Persistent EC2 with encrypted EBS, stopped when idle |

## What it changed for us

Without FSx for Lustre, experimental workers repeatedly staged large chromosome pVCFs
from S3. The filesystem gave multiple workers a common path to the same inputs and made
repeated chromosome-level tests easier.

It did not make every first read fast. The first access could still fetch file data from
S3. Repeated tests improved after the needed chromosomes were hydrated. Meanwhile, the
filesystem continued costing money even when the EC2 instances were stopped. When that
tradeoff stopped being worthwhile, we copied the durable development files to S3,
verified the copy, and deleted the temporary filesystem.

## Cold and warm reads

An FSx for Lustre filesystem can be connected to an S3 prefix through a **data repository
association**. File metadata can be present before all file data is resident on Lustre.
The first read can therefore hydrate data from S3 and behave like a cold cache. Later
reads can be much faster.

Do not benchmark FSx for Lustre from a single first read and call that steady-state
performance. Record separately:

- Time to make or import the namespace.
- Cold-read time.
- Warm-read time.
- Compute time after input is available.
- Export or backup time.

If an experiment repeatedly uses only a few chromosomes, hydrate those objects first and
confirm their availability before starting many dependent jobs.

## Network requirements

The filesystem and workers must have compatible networking:

- Same VPC, or explicitly supported and routed connectivity.
- Subnets and route tables that permit communication.
- Security groups allowing the Lustre protocol between workers and the filesystem.
- DNS resolution available to the workers.
- Permissions required by the FSx for Lustre data repository association.

Provision these relationships with Terraform. Do not paste a filesystem DNS name into a
public guide or hard-code it into the scientific pipeline.

## Mounting on Batch workers

Mount Lustre in the EC2 launch-template bootstrap so it exists before containers start.
The exact client package and mount command depend on the AMI and filesystem configuration,
so keep the tested bootstrap in the private infrastructure repository.

The pattern is:

```text
EC2 starts
    -> installs or verifies the filesystem client
    -> creates a host mount directory
    -> mounts FSx for Lustre
    -> ECS starts the Batch task
    -> the job definition bind-mounts the host directory into the container
```

Test all of these separately:

1. The EC2 host sees the mount.
2. The task container sees the expected directory.
3. The job can read a known small file.
4. The job can write only where intended.
5. A second worker can see the shared result when sharing is required.

Use a read-only container mount for immutable inputs whenever possible. Give scratch and
export directories separate write permissions.

## Avoiding contention

A shared filesystem removes repeated staging but does not create unlimited bandwidth.
Hundreds of workers scanning the same large compressed file can still contend for storage
and decompression resources.

For large pVCFs we found it useful to:

- Partition work by chromosome or non-overlapping region.
- Avoid reopening the same pVCF once per sample.
- Query all needed samples together and transform the result afterward.
- Limit concurrency based on measured throughput rather than only available vCPUs.
- Keep temporary decompression on worker-local EBS when practical.

## Cost and lifecycle

FSx for Lustre storage continues to cost money while compute instances are stopped. That
is the important difference from ephemeral Batch workers.

Before creating it, record:

- Intended lifetime.
- Provisioned storage and throughput.
- Data that must be exported to S3.
- Owner responsible for deletion.
- A review or expiration date.

Before deleting it:

```text
No jobs are using the mount
    -> durable outputs copied to S3
    -> object and byte counts compared
    -> checksums recorded for important artifacts
    -> final inventory saved
    -> exact filesystem confirmed
    -> filesystem deleted
```

Terraform can remove the filesystem, but it cannot decide whether unexported results are
scientifically disposable. Make backup verification a human decision.

## When not to use FSx for Lustre

Do not add FSx for Lustre simply because a workflow is large. Prefer S3 plus local EBS
when each object is read once, jobs are independent, or the filesystem would remain idle
most of the month. The operational and storage costs are justified mainly by repeated
shared reads or software that requires filesystem semantics.

## See also

- [Terraform for AWS](terraform-aws.md) — define the filesystem and Batch environment
- [Nextflow on AWS Batch](nextflow-aws-batch.md) — staging and local-disk behavior
- [Moving Data in AWS](data-movement-aws.md) — import, export, and verification
