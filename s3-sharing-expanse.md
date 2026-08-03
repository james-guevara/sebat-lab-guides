# Sharing Data via S3 on Expanse

How to publish a dataset from Expanse so an outside collaborator can download it
with standard S3 tools — no Expanse account, no SSH, no VPN needed on their end.

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
  someone not approved for it.

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

cp -r /expanse/projects/sebat1/j3guevar/my_results/* \
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
> Could you please:
>
> 1. Create an S3 access key / secret key pair scoped to **only** the
>    `smith-lab-data` bucket — matching how the existing `broad-data` and
>    `pennstate-data` buckets are configured. Read-only is fine (or read-write
>    if I need them to upload data back).
> 2. Confirm the endpoint URL the collaborator should use for this bucket, and
>    register the bucket server-side if that's needed in addition to creating
>    the directory.
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

> **On endpoints:** the only endpoint confirmed working is
> `https://sebat.s3.sdsc.edu`, with **path-style** addressing. Per-bucket
> hostnames like `https://broad-data.s3.sdsc.edu` resolve in DNS but return
> `503 Service Unavailable`, so don't assume `<your-bucket>.s3.sdsc.edu` works.
> Bare `https://s3.sdsc.edu` also 503s. Use whatever hostname SDSC confirms in
> Step 3; the commands below assume the path-style form.

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
  `NoSuchBucket`).

One thing still unconfirmed: whether a plain `mkdir` is sufficient to register a
new bucket server-side, or whether SDSC must also create it. The existing buckets
show a mix — `sebat`, `broad-data`, and `pennstate-data` have server-side
metadata under `.minio.sys/buckets/`, while `gimena_data`, `kun-data`, and `refs`
do not, suggesting those were made with `mkdir` alone. It couldn't be tested from
our account because a bucket-scoped key can't see other buckets either way. This
is why Step 3 asks SDSC to confirm.

The evidence leans toward `mkdir` being sufficient: server-side metadata only
appears for prefixes that have been written *through the S3 API*, and plenty of
directories that are served fine over S3 have no metadata at all. So the absence
of metadata for `kun-data` and friends is expected regardless of how they were
created, and isn't evidence that they're broken.
