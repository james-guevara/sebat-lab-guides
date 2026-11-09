# AWS for the Lab

Getting set up in the lab's AWS account, and the things that cost money or a day if
you learn them late. Everything here is Amazon AWS — not to be confused with
[Sharing Data via S3](s3-sharing-expanse.md), which uses the `aws` CLI against SDSC's
S3-compatible endpoint.

Replace `<ACCOUNT_ID>`, `<work-bucket>` and similar placeholders with the real values;
ask whoever administers the account. Don't commit account IDs or keys to this repo.

## The short version

| You want to | Do this |
|---|---|
| Run day-to-day commands | A named profile (`aws --profile <you>`), not the admin one |
| Give an EC2 box S3 access | Attach an **instance profile** — never copy keys onto it |
| Read another org's bucket | Their side must allow it too. Test `GetObject`, not just `ls` |
| Copy TBs between accounts | On EC2 **in the same region**. Through your laptop it costs ~17× more |
| Use an image you built | Push it to ECR. Workers can't see your machine's Docker daemon |
| Not get a surprise bill | Lifecycle rule on scratch prefixes + a CloudWatch billing alarm, *before* you start |

## 1. Profiles: use a scoped one, keep admin for admin

Credentials live in `~/.aws/credentials` as named profiles:

```bash
aws --profile <you> s3 ls s3://<work-bucket>/
export AWS_PROFILE=<you>          # or set it for the session
```

Keep an admin profile for IAM and account-level changes, and a normal user profile for
everything else. The reason is blast radius, not ceremony: a mistyped `aws iam` command
under admin can lock people out of the account.

One `zsh` gotcha when scripting this — `zsh` does **not** word-split unquoted variables,
so the common trick of stashing flags in a variable silently breaks:

```bash
R="--profile <you> --region us-east-1"
aws $R batch describe-job-queues     # zsh: passes ONE argument, "aws: Invalid choice"
```

Write the flags out, or use an array.

## 2. Roles beat keys on machines

An EC2 instance should get an **instance profile** (an IAM role it assumes
automatically). The AWS CLI and SDKs then find credentials with no files, no env vars,
and nothing to leak or rotate:

```bash
aws ec2 run-instances ... --iam-instance-profile Name=<InstanceProfile>
# then, on the box, this just works:
aws s3 cp s3://<work-bucket>/x .
```

Same for AWS Batch: the job role gives every task its permissions.

**Third-party keys are the exception** — when a data provider issues you an access key
for *their* account, there's no role to assume. Put it in Secrets Manager and have jobs
fetch it at runtime rather than pasting it into scripts:

```bash
aws secretsmanager get-secret-value --secret-id <name> --query SecretString --output text
```

Two hard-won details:

- **Check whether the stored copy still works before building on it.** A key sitting in
  Secrets Manager since 2023 will happily return `InvalidClientTokenId`, and the failure
  surfaces as a confusing 403 halfway through a pipeline.
- **Never pass secrets with `docker run -e KEY=value`.** Command-line arguments are
  world-readable in the process list for the life of the container — any `ps` or
  `pgrep -af` prints them, including into log files and terminal scrollback. Use
  `--env-file` with a `0600` file, ideally on `tmpfs` (`/dev/shm`), deleted on exit.

## 3. Cross-account S3: both sides must allow it

To read a bucket owned by another organisation, **two** policies must permit it: their
bucket policy (or your key's identity policy, if they issued you a user) *and* your
side's identity policy. Adding a policy on your own bucket does nothing for access to
theirs, and vice versa. This is easy to get backwards and produces a flat `AccessDenied`
either way.

**`ListBucket` succeeding does not mean `GetObject` will.** They're separate actions and
providers often grant them differently:

```bash
aws --profile <provider> s3 ls s3://<their-bucket>/            # works
aws --profile <provider> s3 cp s3://<their-bucket>/f .         # 403 Forbidden
```

Providers also condition access on *where the request comes from*. A policy with an
`aws:SourceIp` condition can allow reads from inside AWS and deny them from your laptop
— same key, same object, different answer. If a read 403s locally, try it from an EC2
instance before concluding the key is broken.

So: **test an actual object read, early**, and from the environment that will do the real
work. A whole staging plan can rest on an assumption that `ls` validated nothing about.

## 4. Moving data: region is everything

Transfers *within* a region are free; data leaving AWS is billed around $0.09/GB. That
turns a routing decision into a four-figure one:

| 13 TB copy | Cost |
|---|---|
| Provider bucket → EC2 in the same region → your bucket | ~$0 transfer |
| Provider bucket → your laptop → your bucket | **~$1,100** |

So run bulk copies **on an EC2 instance in the bucket's region**, never streamed through
a workstation.

Note also that a server-side `aws s3 cp s3://a s3://b` requires *one* credential with
read on the source and write on the destination. Across accounts you usually don't have
that, so the copy has to stream through an instance — one leg with their key, the other
with your role.

## 5. ECR: where your own images have to live

Batch workers and other ephemeral machines can only pull from a registry. An image built
on your head node exists nowhere they can reach, so pushing it to ECR isn't an
optimisation — it's what makes it usable:

```bash
aws ecr create-repository --repository-name <name>
aws ecr get-login-password | docker login --username AWS \
    --password-stdin <ACCOUNT_ID>.dkr.ecr.<region>.amazonaws.com
docker tag <name>:1.0 <ACCOUNT_ID>.dkr.ecr.<region>.amazonaws.com/<name>:1.0
docker push <ACCOUNT_ID>.dkr.ecr.<region>.amazonaws.com/<name>:1.0
```

- Build with `--platform linux/amd64`. Apple Silicon defaults to `arm64`, which won't run.
- Do the push **on an in-region instance** if the image is large; a multi-GB push from
  home is slow, and the pull from Docker Hub is faster there too.
- **Pin by digest, not tag**, for anything reproducible. `:latest` and even `:1.0` are
  mutable; `@sha256:…` is not.
- Public registries (GHCR, Docker Hub) can be pulled directly. Mirroring to ECR buys
  in-region speed and insulation from upstream `:latest` drift, and avoids Docker Hub's
  anonymous rate limits when hundreds of tasks pull at once.

## 6. Cost guardrails — set these up first

Institutional accounts often have billing managed upstream, which means **you may have
no Cost Explorer access at all**: a runaway job is invisible to you until the
institution's bill arrives. Compensate deliberately.

**Lifecycle rules on scratch prefixes.** Staged inputs are the classic forgotten cost —
13 TB in S3 Standard is roughly $283/month. Expire them automatically:

```bash
aws s3api put-bucket-lifecycle-configuration --bucket <work-bucket> \
  --lifecycle-configuration '{"Rules":[{
    "ID":"expire-staged-after-7-days","Status":"Enabled",
    "Filter":{"Prefix":"staged/"},
    "Expiration":{"Days":7},
    "AbortIncompleteMultipartUpload":{"DaysAfterInitiation":2}}]}'
```

The multipart clause matters: failed big uploads leave paid-for fragments that never
appear in `s3 ls`.

**Don't reach for Infrequent Access or Glacier for short-lived data.** They look cheaper
per GB but carry 30-day minimum billing, so a one-week stage costs *more* there than in
Standard.

**A CloudWatch billing alarm** is the cheapest insurance available and takes a minute.

**Watch burstable instances.** `t2`/`t3`/`t4g` are cheap because you get only a baseline
share of CPU (30% for `t3.large`), earning "credits" when idle and spending them when
busy. For sustained compute this bites two ways:

- In `standard` mode you're throttled to baseline once credits run out — a job silently
  runs ~3× slower.
- In `unlimited` mode (the `t3` default) you keep full speed and are billed for surplus,
  quietly, which is worse when you can't see the bill.

```bash
aws ec2 describe-instance-credit-specifications --instance-ids <id>   # which mode?
```

For anything CPU-bound, use a fixed-performance family (`c`/`m`/`r`) and stop it when
idle. Also: **credits are irrelevant to a load average of 1.0 on an 8-core box** — check
whether your tool is actually multithreaded before buying more cores.

## 7. The head-node pattern

For pipelines, one small persistent EC2 instance acts as the driver: it holds the repos,
runs the workflow manager in `tmux`, and submits work to Batch. Workers are ephemeral and
hold nothing.

```bash
ssh ubuntu@<ip>       # instance profile gives it S3/ECR access; no keys needed
tmux                  # so the run survives your laptop closing
```

Practical notes:

- **The public IP changes every time it stops and starts.** Re-query rather than trusting
  a noted address; use an Elastic IP if that gets annoying.
  ```bash
  aws ec2 describe-instances --instance-ids <id> \
      --query 'Reservations[].Instances[].PublicIpAddress' --output text
  ```
- **Resize while stopped, it's free** — `modify-instance-attribute --instance-type`. Pick
  the size before you start a long job, not after.
- **The root volume defaults small** (often 8 GB). Pulling a couple of multi-GB images
  fills it. Grow it live, no downtime:
  ```bash
  aws ec2 modify-volume --volume-id <vol> --size 100
  sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1
  ```
- **Give it enough RAM to be a driver.** A workflow manager tracking hundreds of
  concurrent jobs on a 2 GB box is asking for an OOM that kills the run.
- **Stop it when you're done.** It bills by the hour whether or not anything is running.

## See also

- [Nextflow on AWS Batch](nextflow-aws-batch.md) — porting a SLURM pipeline to Batch
- [Nextflow on Expanse](nextflow-expanse.md) — the SLURM side
- [Containers on Expanse](containers-expanse.md) — why images get built elsewhere
