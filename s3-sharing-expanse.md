# Sharing Data via S3 on Expanse

How to publish a dataset from Expanse so an outside collaborator can download it
with standard S3 tools — no Expanse account, no SSH, no VPN needed on their end.

## Is this the right method?

Check this first. A dedicated bucket is the most involved option, because the
access keys must be created by SDSC — so start by asking whether you need one.

| Situation | Use this |
|---|---|
| They have an Expanse/SDSC account | A directory ACL — no keys, no ticket, no S3 |
| **One-off transfer, or few enough files to tar up** | **[Presigned URL](#recommended-for-one-off-transfers-presigned-urls) — no ticket, works today** |
| Very large or unreliable transfer | [Globus](globus-expanse.md) — resumable and checksummed |
| Many files, ongoing or self-service access, or needed for more than 7 days | A dedicated bucket — **the rest of this guide** |

**Try a presigned URL first.** It uses keys you already have, so SDSC isn't
involved at all and you can do it in the next five minutes. The dedicated-bucket
route below is for when a link per file stops being practical.

The only thing that genuinely requires an SDSC ticket is **creating the access
keys** for a new bucket. Creating the bucket itself is just `mkdir` — see
[Verified behaviour](#verified-behaviour).

## Why this works

SDSC runs an S3 server (MinIO) on top of our project storage. Files you copy
into a folder on Expanse become downloadable over the internet immediately —
there is no upload or sync step, because the S3 server reads the same directory.

**The key idea: each top-level folder under `/expanse/projects/sebat1/s3/data/`
is its own bucket.** Not a subfolder of one big bucket — a separate bucket, with
its own access keys.

| On Expanse (a normal directory) | Over the network |
|---|---|
| `/expanse/projects/sebat1/s3/data/sebat/` | `s3://sebat/` |
| `/expanse/projects/sebat1/s3/data/broad-data/` | `s3://broad-data/` |

Each bucket gets its own key pair, and a key only works for its own bucket.
Someone holding the `broad-data` keys cannot see `sebat`, and vice versa —
verified: our `sebat` key gets `AccessDenied` on every other bucket. That
isolation is what makes this safe to hand out.

There are already several collaborator buckets set up this way (`broad-data`,
`pennstate-data`, `gimena_data`, `kun-data`), so you're following an existing
pattern, not inventing one.

## Before you start

- You need write access to `/expanse/projects/sebat1/s3/data/` (i.e. you're in
  the lab's Expanse allocation).
- This works well up to a few TB. For very large or unreliable transfers,
  consider [Globus](globus-expanse.md) instead.
- **Anything in the bucket is readable by anyone holding that bucket's key.** Do
  not put controlled-access data (SFARI, dbGaP) in a bucket whose keys will go to
  someone not approved for it. That includes individual-level derived data —
  per-sample PGS scores or DNM callsets keyed to cohort IDs are still
  individual-level cohort data. Aggregate/summary output generally isn't.
- **"We generated it" doesn't lift the cohort's restrictions.** Sequencing data
  the lab produced itself on SPARK or SSC samples is still SPARK/SSC data. If in
  doubt, check the data use agreement before creating the bucket, not after.

## Step 1 — Pick a bucket name

Use **lowercase letters, numbers, and hyphens only**. No underscores, no
capitals, no dots.

- Good: `smith-lab-data`, `mouse-rnaseq-2026`
- Broken: `smith_lab_data`

This is not a style preference. Bucket names can end up in a hostname, and the
AWS CLI rejects underscores outright (`Invalid endpoint`). The existing
`gimena_data` bucket has this problem and can only be reached path-style.

## Step 2 — Create the folder and add your data

```bash
ssh expanse

mkdir /expanse/projects/sebat1/s3/data/smith-lab-data

cp -r /expanse/projects/sebat1/$USER/my_results/* \
      /expanse/projects/sebat1/s3/data/smith-lab-data/

ls -la /expanse/projects/sebat1/s3/data/smith-lab-data/
du -sh  /expanse/projects/sebat1/s3/data/smith-lab-data/
```

This counts against the project's storage allocation — it is not separate quota.
If the data already lives on Expanse and you don't need two copies, `mv` it, or
hard-link it (`cp -al`) if it's on the same filesystem.

## Step 3 — Request access keys from SDSC

Key creation is **not** self-service. Confirmed by testing: `CreateBucket`
returns `AccessDenied` even with our existing project keys, and the S3 user
accounts are not stored in our project directory. You must open a ticket.

Email SDSC support (`support@sdsc.edu`, or whoever you normally email about
Expanse) and ask for a key pair scoped to the new bucket. **Also ask them to
confirm the endpoint hostname** — see the note in Step 4 for why.

Template:

> Hello,
>
> We have a MinIO/S3 setup on Expanse project storage backed by
> `/expanse/projects/sebat1/s3/data/` (project `sebat1`, allocation `ddp195`).
> I've created a new folder `smith-lab-data` there and would like to share it
> with an external collaborator.
>
> Could you please create an S3 access key / secret key pair scoped to **only**
> the `smith-lab-data` bucket — matching how the existing `broad-data` and
> `pennstate-data` buckets are configured? Read-only is fine (or read-write if I
> need them to upload data back).
>
> Thanks,
> <your name>

Existing key pairs are stored as small text files one level up, e.g.
`/expanse/projects/sebat1/s3/broad-data.txt`. Follow that convention so the next
person can find yours:

```bash
chmod 600 /expanse/projects/sebat1/s3/smith-lab-data.txt
```

## Step 4 — Verify it works before you send anything

> **On endpoints:** always use `https://sebat.s3.sdsc.edu` with **path-style**
> addressing, whatever your bucket is called. That hostname is not specific to the
> `sebat` bucket — it serves every bucket in the project, verified by reaching
> `gimena_data` through it with that bucket's own key.
>
> Do **not** assume `<your-bucket>.s3.sdsc.edu` works. Per-bucket hostnames like
> `https://broad-data.s3.sdsc.edu` resolve in DNS but return
> `503 Service Unavailable`, and bare `https://s3.sdsc.edu` 503s too.

Set up a profile with path-style addressing. In `~/.aws/config`:

```ini
[profile smith-lab]
s3 =
    addressing_style = path
```

Then, with the new keys in `~/.aws/credentials`:

```bash
# List the bucket contents
aws --profile smith-lab s3 ls s3://smith-lab-data/ \
    --endpoint-url https://sebat.s3.sdsc.edu

# Confirm the key sees ONLY this bucket
aws --profile smith-lab s3 ls --endpoint-url https://sebat.s3.sdsc.edu

# Confirm a download actually works
aws --profile smith-lab s3 cp s3://smith-lab-data/somefile.txt . \
    --endpoint-url https://sebat.s3.sdsc.edu
```

If the second command lists buckets other than yours, the key is not scoped
correctly — go back to SDSC before sharing it.

## Step 5 — Send your collaborator the instructions below

Everything past this line is written for someone with no SDSC account. Copy it
into your email and fill in the placeholders. **Send the secret key separately**
from the rest — different email, Slack DM, or phone.

---

### Downloading the data (instructions for the recipient)

The data is on an S3-compatible server at SDSC. It is **not** Amazon AWS, so
every command needs the `--endpoint-url` flag shown below, and the profile needs
path-style addressing. Other than that, it behaves like normal S3.

**1. Install the AWS CLI.** This is just the client tool; you do not need an
Amazon account:

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install

# or with conda/pip
pip install awscli
```

**2. Save the credentials.** In `~/.aws/credentials`:

```ini
[sdsc]
aws_access_key_id = ACCESS_KEY_HERE
aws_secret_access_key = SECRET_KEY_HERE
```

And in `~/.aws/config` — the `addressing_style` line is required:

```ini
[profile sdsc]
s3 =
    addressing_style = path
```

```bash
chmod 600 ~/.aws/credentials
```

**3. List the files:**

```bash
aws --profile sdsc s3 ls s3://BUCKET_NAME/ --endpoint-url https://ENDPOINT_HERE
```

**4. Download everything into a local folder:**

```bash
aws --profile sdsc s3 sync s3://BUCKET_NAME/ ./local-folder/ \
    --endpoint-url https://ENDPOINT_HERE
```

Or a single file:

```bash
aws --profile sdsc s3 cp s3://BUCKET_NAME/path/to/file.vcf.gz . \
    --endpoint-url https://ENDPOINT_HERE
```

`sync` is restartable — if it dies partway, run the same command again and it
only fetches what's missing. Recommended for large transfers.

**5. Only if you need to UPLOAD data back.** The server is an older MinIO that
rejects the newer AWS CLI's chunked uploads with
`MissingContentLength: You must provide the Content-Length HTTP header`.
Downloads are unaffected. To fix, set these before uploading:

```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

aws --profile sdsc s3 cp ./myfile.txt s3://BUCKET_NAME/ \
    --endpoint-url https://ENDPOINT_HERE
```

Verified against aws-cli 2.30.6: the upload fails without these and succeeds
with them. Equivalent config-file form:

```ini
[profile sdsc]
request_checksum_calculation = when_required
response_checksum_validation = when_required
s3 =
    addressing_style = path
```

**Troubleshooting:**

| Symptom | Cause |
|---|---|
| Empty output, no error | Missing `--endpoint-url` — you queried real AWS |
| `MissingContentLength` on upload | Set the two checksum variables above |
| `503 Service Unavailable` | Wrong endpoint hostname — ask for the right one |
| `Invalid endpoint` | Underscore in the bucket name; use path-style addressing |
| `InvalidAccessKeyId` | Key typo, or wrong `--profile` |
| `AccessDenied` on a bucket | Your key is scoped to one bucket; check the name |
| `SSL: CERTIFICATE_VERIFY_FAILED` | Out-of-date CA bundle; update your CLI/certs |

---

## Recommended for one-off transfers: presigned URLs

For most sharing requests this is all you need, and it's much less work than a
dedicated bucket. A presigned URL is an ordinary HTTPS link with a time-limited
signature embedded in it. It uses **keys you already have**, so there's no ticket,
and the recipient needs no credentials, no AWS CLI, and no SDSC account.

The file has to live in a bucket you already hold keys for — in practice, put it
somewhere under `/expanse/projects/sebat1/s3/data/sebat/`. Then:

```bash
aws --profile sebat s3 presign s3://sebat/path/to/file.tsv \
    --expires-in 604800 \
    --endpoint-url https://sebat.s3.sdsc.edu
```

That prints a long URL. Send it. The recipient runs:

```bash
curl -O "PASTE_THE_URL_HERE"
```

Verified against the live server: the URL returns HTTP 200 with the correct
content and no credentials, while the same path without the signature returns
`403 AccessDenied`. So the signature — not public access — is what grants the
download.

**Watch the expiry limit.** The maximum is 7 days (`604800` seconds), enforced by
the server. The AWS CLI does **not** warn you if you exceed it — it happily
prints a URL that fails with `HTTP 400 AuthorizationQueryParametersError` when
anyone tries to use it. Confirmed: `604800` works, `604801` produces a
dead link. If you need longer than a week, use a bucket and keys instead.

**Staging inside `sebat` is safe.** The signature grants access to that one object
and nothing else — not the bucket, not the rest of the ~22 TB. You're handing out a
link, never a key. (Standard data-use rules still apply to whatever is *in* the
file; see [Before you start](#before-you-start).)

### Many files: tar them into one object

There's no way to presign a directory, and the recipient can't browse a listing —
it's strictly one URL per object. So rather than sending twenty links, send one:

```bash
cd /expanse/projects/sebat1/$USER
mkdir -p /expanse/projects/sebat1/s3/data/sebat/outgoing
tar czf /expanse/projects/sebat1/s3/data/sebat/outgoing/results-2026-08.tar.gz results/

aws --profile sebat s3 presign s3://sebat/outgoing/results-2026-08.tar.gz \
    --expires-in 604800 --endpoint-url https://sebat.s3.sdsc.edu
```

One link, one resumable download, and it keeps the directory structure. This is
the practical answer up to a few hundred GB going to one person. Past that, or for
ongoing access, use a dedicated bucket.

Caveats:

- Anyone with the link can download it during the validity window — treat the URL
  itself as the credential and don't post it publicly.
- The link stops working if the file moves or is deleted.
- Resuming a partial download (`curl -C -`) relies on HTTP range requests, which
  haven't been tested against this server. Verify on a throwaway file before
  depending on it for a very large transfer.
- If they need longer than 7 days, just issue a fresh URL — but if you find
  yourself reissuing repeatedly, switch to a bucket.

## Housekeeping

- **These keys don't expire.** When the collaboration ends, email SDSC to revoke
  the pair, and delete the folder if the data doesn't need to stay.
- **Never reuse the `sebat` keys for sharing.** That bucket holds ~22 TB
  including controlled-access cohort data. Always a new bucket per collaborator.
- **Deleting data:** removing files on Expanse with `rm` removes them from S3
  too — they're the same files. One wrinkle: objects that were *uploaded through
  the S3 API* also get a small metadata entry under
  `.minio.sys/buckets/<bucket>/<key>/fs.json`, which a filesystem `rm` leaves
  behind. It's harmless (a few hundred bytes), but if you want a clean delete,
  remove those objects with `aws s3 rm` instead of `rm`. Files you created with
  `cp`/`rsync` have no such metadata and delete cleanly.

## Verified behaviour

Tested August 2026 against the live server:

- A file created on Expanse with `cp`/`printf` appeared over S3 **immediately**
  and downloaded correctly — no sync step, confirmed.
- A file uploaded through the S3 API appeared on the Expanse filesystem
  immediately, with normal ownership and permissions.
- `CreateBucket` via the API is denied, so new buckets need an SDSC ticket.
- Our bucket-scoped key returns `AccessDenied` for all other buckets, including
  names that don't exist (S3 masks existence rather than returning
  `NoSuchBucket`). Unauthenticated requests behave the same way, so there is no
  way to probe whether a given bucket exists from outside.
- Presigned URLs work: HTTP 200 with no credentials, `403` without the
  signature, and a server-enforced 7-day maximum that the CLI does not warn about.
- Server-side metadata under `.minio.sys/buckets/<bucket>/` is only created when
  an object is written **through the S3 API**. Files created with `cp`, and
  objects merely read over S3, produce none.
- A bucket with no such metadata is fully functional: `gimena_data` has none, and
  its key lists it normally while being denied on `sebat`. The directory itself is
  the bucket.

**The directory is the bucket — no server-side registration step is needed.**
This was tested directly: the `gimena_data` bucket has *no* metadata under
`.minio.sys/buckets/`, and its key nonetheless lists it fine (and is correctly
denied on `sebat`). So `.minio.sys/buckets/` is per-object metadata, not a bucket
registry, and its absence says nothing about whether a bucket works. That matches
the backend in use: `format.json` reports `"format":"fs"`, MinIO's filesystem
mode, where a bucket is a top-level directory under the data root.

So creating the folder is genuinely all there is to it. **What `mkdir` does not do
is create credentials** — that part always needs SDSC, which is the real reason
for the ticket in Step 3.

The one residual unknown is narrow: we could never watch a brand-new top-level
directory be served, because that needs a key we don't have. But the server
demonstrably reads the filesystem live — a file created with `cp` inside an
existing bucket appears over S3 immediately — so there's no reason to expect a new
directory to behave differently. If a new bucket ever does fail to appear, ask
SDSC to register it; otherwise assume it just works.
