# Moving Data in AWS

Large genomic datasets make the route as important as the copy command. The safe default
is to move computation to the data, keep durable copies in S3, use temporary storage only
while it helps, and verify every large transfer before deleting the source.

Examples here are sanitized. Controlled-data bucket names, participant IDs, credentials,
and private endpoints belong in a private runbook.

## Choose the route first

| Source and destination | Recommended method |
|---|---|
| S3 to Batch, one read | Stage to worker-local encrypted EBS |
| S3 to many repeated Batch reads | Import or hydrate on FSx for Lustre |
| FSx for Lustre to durable storage | Export or copy to S3, then verify |
| Expanse to AWS | Run the transfer on an approved endpoint; do not route through a laptop |
| AWS to a collaborator with Globus | Stage an approved export on a registered endpoint |
| Small non-controlled result | Scoped S3 access or a short-lived presigned URL |

Confirm data-use and institutional rules before moving controlled data between systems.
Technical access does not itself authorize a transfer.

## Region and egress

Find the bucket region before designing a bulk copy:

```bash
aws s3api get-bucket-location --bucket <source-bucket>
aws s3api get-bucket-location --bucket <destination-bucket>
```

Keep source, compute, temporary storage, and destination in the same AWS region when
possible. Do not stream terabytes through a workstation: it is slower, fragile, and can
incur avoidable internet egress. For cross-account transfers, run the copy on an approved
EC2 or Batch worker in the source region with separately scoped read and write access.

## Copy to S3

For a directory tree:

```bash
aws s3 sync <local-directory>/ s3://<bucket>/<prefix>/ \
  --only-show-errors
```

For a deliberate immutable snapshot, prefer a versioned prefix containing a date or run
identifier. Avoid syncing unrelated project roots into one broad prefix.

Do not use `--delete` casually. It makes the destination mirror source deletions and can
remove valid data. If it is genuinely required, run a dry run and inspect every target:

```bash
aws s3 sync <source>/ s3://<bucket>/<prefix>/ --delete --dryrun
```

## Verify a transfer

An exit code of zero is necessary but not enough. Create a normalized local inventory
with the repository helper:

```bash
python3 scripts/make_inventory.py \
  <local-directory> \
  > local-inventory.tsv

aws s3api list-objects-v2 \
  --bucket <bucket> \
  --prefix <prefix>/ \
  --output json \
  > s3-inventory.json
```

The helper works on macOS and Linux and emits relative path and byte count. The raw S3
JSON remains useful evidence, but it must be normalized relative to the selected prefix
before doing a path-by-path comparison. For large recurring transfers, add an S3
inventory normalizer to the private runbook rather than comparing differently shaped
listings by eye.

Record at least:

- File or object count.
- Total bytes.
- Missing or unexpected paths.
- Checksums for important outputs.
- Timestamp, source, destination, and command used.

S3 ETags are not universally MD5 checksums: multipart uploads and some encryption modes
produce different values. Generate explicit SHA-256 values when content identity matters:

```bash
python3 scripts/make_inventory.py \
  --sha256 \
  <local-directory> \
  > local-inventory-sha256.tsv
```

For very large collections, a complete checksum pass may itself be expensive. State
whether validation used all-object checksums, selected checksums, counts and bytes, or an
S3 Inventory report.

## Expanse and Globus

Use Globus for large transfers when both endpoints are registered. It provides restart,
monitoring, and integrity checking without keeping an SSH session alive. See
[Globus Setup](globus-expanse.md).

For Expanse-to-AWS movement:

1. Confirm the approved source and destination.
2. Build a source manifest.
3. Transfer from Expanse or an approved transfer node—not through a laptop.
4. Build a destination inventory.
5. Compare counts and bytes.
6. Retain the transfer task ID or logs.
7. Delete temporary copies only after verification.

## Batch staging

Batch workers should receive access through IAM roles, not copied access keys. Prefer one
of two patterns:

```text
S3 object -> local EBS -> task -> result -> S3
```

or, for repeatedly shared large inputs:

```text
S3 data repository -> FSx for Lustre -> many tasks -> S3 results
```

Size local EBS for compressed input, indexes, decompressed or temporary data, output, and
headroom. A 500 GB compressed pVCF does not fit safely on a 500 GB volume once tools write
temporary files.

## Lifecycle and deletion

Temporary prefixes should have an explicit retention period. Configure lifecycle rules
for staged data and incomplete multipart uploads, but do not apply broad expiration rules
to durable results.

Before deleting a large source:

1. Resolve the exact prefix or filesystem.
2. Check that no active job depends on it.
3. Verify the destination inventory.
4. Save the deletion manifest.
5. Use a dry run or list operation to inspect scope.
6. Delete only the intended prefix.

Never ask an AI agent to recursively delete an unresolved variable, home directory,
workspace root, bucket root, or filesystem mount.

## Information safe for a public guide

Publish the method, placeholders, and verification logic. Keep these private:

- Real controlled-data paths and sample identifiers.
- AWS account numbers and IAM principals.
- VPC, subnet, security-group, and filesystem IDs.
- Credentials and presigned URLs.
- Private transfer endpoints.
- Terraform state and environment-specific variables.

## See also

- [AWS for the Lab](aws-setup.md) — IAM and cross-account access
- [FSx for Lustre with Batch](fsx-aws.md) — repeated shared reads
- [Sharing Data via S3](s3-sharing-expanse.md) — SDSC S3-compatible sharing
- [Globus Setup](globus-expanse.md) — managed large transfers
