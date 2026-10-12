# Accessing Sebat archival storage through Globus

Verified October 11, 2026, using directory listings and a completed archive-to-project restore.

## Collection and paths

Use **SDSC RDS Storage**, collection ID:

```text
a9f6238a-1eb4-4bfb-a9b6-8bd6c4672c7f
```

[Open the collection in Globus File Manager](https://app.globus.org/file-manager?origin_id=a9f6238a-1eb4-4bfb-a9b6-8bd6c4672c7f&origin_path=%2Fprojects%2Fsebat%2Fps-sebat%2F)

| Purpose | Path inside this Globus collection |
|---|---|
| Archive roots | `/projects/sebat/ps-sebat/archive/`, `/projects/sebat/ps-sebat/archive2/`, `/projects/sebat/ps-sebat/archive3/` |
| Lab data within archive2 | `/projects/sebat/ps-sebat/archive2/sebat-lab/` |
| Lilia lab backups | `/projects/sebat/ps-sebat/archive2/sebat-lab/Lilia_Lab/` |
| Active Expanse project storage | `/projects/sebat1/` |

The collection's `/projects/sebat1/` maps to `/expanse/projects/sebat1/` when accessed through Expanse SSH. Archive paths above are Globus paths; do not assume they are mounted at the same paths on a login node. Other archive trees may have different layouts: list before assuming a `sebat-lab/` subdirectory.

**SDSC HPC Projects** (`46cad570-3f0d-4bfc-8ebc-ce2c13f13df7`) did not expose these Sebat paths in our session. Use the RDS collection for this procedure. A personal Globus Connect Personal endpoint is unnecessary for RDS archive-to-project restores.

## Authentication and browsing

Authenticate with your own institution/ACCESS identity that has access to the lab storage. Collection access and linked identities are user-specific; do not assume another lab member's authorization grants yours.

```bash
globus login
globus session show
RDS_COLLECTION=a9f6238a-1eb4-4bfb-a9b6-8bd6c4672c7f
globus ls "$RDS_COLLECTION:/projects/sebat/ps-sebat/"
globus ls "$RDS_COLLECTION:/projects/sebat/ps-sebat/archive2/sebat-lab/"
globus ls "$RDS_COLLECTION:/projects/sebat1/"
```

If prompted for additional collection consent or identity authentication, follow the CLI-provided authorization URL/command. Refresh an expired identity with `globus session update YOUR_IDENTITY`. On James's Apple Silicon Mac, the working CLI invocation is `arch -arm64 ~/.local/bin/globus`.

This is a GCS v5 mapped collection: `globus endpoint show` is not its metadata command. `globus gcs collection show` may require separate management consent; a successful `globus ls` is sufficient to establish browsing access, and management consent is not needed merely to list or transfer files.

## Restore a directory to Expanse project storage

Use the same collection for both sides, with different source and destination paths. Browse the source first, check destination capacity, and choose an explicit destination. This copies the archive; it does not move or delete the archived copy.

```bash
RDS_COLLECTION=a9f6238a-1eb4-4bfb-a9b6-8bd6c4672c7f
ARCHIVE_SOURCE=/projects/sebat/ps-sebat/archive2/sebat-lab/PATH_TO_DATA/
PROJECT_DEST=/projects/sebat1/YOUR_DIRECTORY/RESTORED_DATA/

globus transfer "$RDS_COLLECTION:$ARCHIVE_SOURCE" \
  "$RDS_COLLECTION:$PROJECT_DEST" \
  --recursive --verify-checksum --label "Restore archived dataset to Expanse"
```

Record the returned task ID, source, destination, and intended dataset in the project's operations notes. Monitor with:

```bash
globus task show TASK_ID
globus task event-list TASK_ID
```

After `SUCCEEDED`, files are accessible on Expanse under the corresponding `/expanse/projects/sebat1/` destination. Check file counts and expected contents. Transfer checksums verify transport integrity, not sample identity or scientific metadata correctness.

## Verified example: GIGYF1 RNA-seq restore

Source within RDS:

```text
/projects/sebat/ps-sebat/archive2/sebat-lab/genomicsdataanalysis/autism/RNASeq/GIGYF1/igm-storage1.ucsd.edu/180420_K00180_0592_AHTKCLBBXX_PE100_Combo/
```

Restored Expanse path:

```text
/expanse/projects/sebat1/genomicsdataanalysis/autism/RNASeq/GIGYF1/igm-storage1.ucsd.edu/180420_K00180_0592_AHTKCLBBXX_PE100_Combo/
```

Task `3ec31540-c5d6-11f1-9ffc-0affd5e180af` succeeded on October 11, 2026 Pacific (October 12 UTC): 115 files, 50,072,074,519 bytes, zero faults, checksum verification enabled. This restored the full delivery directory, including FASTQs, Reports, and Stats. The original archive was retained.

For historical searches, existing file manifests can locate candidate paths much faster than recursively listing every archive directory. Confirm each candidate with a targeted Globus listing; an old manifest alone does not prove current availability.
