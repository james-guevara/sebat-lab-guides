# Measuring and Characterizing Storage on Expanse

How to answer "how big is this?", "what *is* all this data?", and "what can I
safely delete?" without spending an afternoon waiting on `du`.

All numbers below were measured on Expanse in August 2026 against
`/expanse/projects/sebat1/s3/data/sebat/nf_rare_spark_wes` (3.5 TB, 91,299 files)
in a 16-core `ind-shared` job. Re-measure before quoting them elsewhere; they
depend heavily on metadata cache warmth (see [Gotchas](#gotchas)).

## The one thing to understand first

Expanse has **three different filesystems**, and the fastest method is different
on each. Check which one you're on before anything else:

```bash
df -Th /path/you/care/about | tail -1
```

| Path | Type | Fast path |
|---|---|---|
| `/home/$USER` | NFS | parallel walk |
| `/expanse/projects/sebat1` | **NFS** (637 T, 92% full) | parallel walk — no quota shortcut |
| `/expanse/lustre/projects` | **Lustre** (11 P) | `lfs quota`, `lfs find` — no walk |

Most people assume "Expanse = Lustre". The lab's project space is **NFS**, has no
per-user quota, and every question about it costs a directory walk.

Work in this order:

1. **Don't walk at all** if a quota or an object listing can answer you.
2. **Walk in parallel, inside a job** when you must.
3. **Never walk twice** — save a manifest and query it repeatedly.

> **Login-node rule.** The login nodes have 64 cores shared by the whole cluster,
> and `diskus` grabs every core it can see. SDSC kills heavy login-node processes.
> Anything that walks a large tree belongs in an `ind-shared` job.

## 1. Don't walk: quotas and totals

Instant, because the filesystem already tracks these.

```bash
# Lustre: your total across /expanse/lustre/projects, no walk
lfs quota -h -u $USER /expanse/lustre/projects

# Whole-mount usage (all users)
df -Th /expanse/projects/sebat1
```

Example output, and how to read it:

```
Filesystem  used   quota   limit   grace   files   quota  limit
            15.8T*    0k  9.537T       -   41443       0  2000000
```

The `*` means **over quota**. Drop `-h` to see the grace column, which tells you
whether writes are about to start failing.

There is **no equivalent for `/expanse/projects/sebat1`** — `quota -s` reports
nothing for it. For that filesystem, skip to section 2 or 4.

## 2. One directory, one number: use `diskus`, not `du`

[`diskus`](https://github.com/sharkdp/diskus) walks in parallel. On NFS the win
comes from overlapping thousands of high-latency `stat()` calls, not from it
being written in Rust.

```bash
# already installed for the lab at:
~/.local/bin/diskus -j "$SLURM_CPUS_PER_TASK" /path/to/dir
```

Measured on the 3.5 TB tree:

| Command | Time |
|---|---|
| `du -sh` | 66.3 s |
| `diskus -j 16` | **6.7 s** |

Same answer (`3.5T` vs `3845652258816` bytes), ~10× faster. Always pass
`-j $SLURM_CPUS_PER_TASK` so it respects your allocation instead of grabbing
every core on the node.

## 3. What *is* all this data? Walk once, query forever

`du` and `diskus` only ever give you one number. To decide what to archive you
need composition — by file type, by age, by owner. Do **one** walk that records
everything, then answer every future question from that file.

### The manifest

```bash
find "$TARGET" -printf '%s\t%b\t%T@\t%A@\t%C@\t%U\t%G\t%m\t%i\t%n\t%y\t%p\t%l\n' \
    > manifest.tsv
```

| Field | Meaning | Why it's kept |
|---|---|---|
| `%s` | apparent size (bytes) | the headline number |
| `%b` | 512-byte blocks used | real disk usage; differs from `%s` on sparse files |
| `%T@` | mtime (epoch) | primary archiving signal |
| `%A@` | atime | "never read since written" — see caveat below |
| `%C@` | ctime | metadata change; catches moves/chmod that mtime misses |
| `%U` | uid (**numeric**) | attribution; see the `%u` warning below |
| `%G` | gid | separates `ddp195` / `jsebat-group` / `csd555` data |
| `%m` | mode (octal) | finds group-unreadable data nobody else can inherit |
| `%i` | inode | hardlink de-duplication |
| `%n` | link count | `>1` means deleting one path frees nothing |
| `%y` | type (`f`/`d`/`l`) | keeps dirs and symlinks in the manifest |
| `%p` | path | file type, cohort, pipeline all derive from this |
| `%l` | symlink target | finds dangling links |

**Use `%U`, never `%u`.** `%u` resolves a username per file and never caches.
Measured on the same tree, warm cache: `%U` = **3.5 s**, `%u` = **177.9 s** —
50× slower for output that is otherwise byte-identical. Map uids to names once,
afterwards, from `getent passwd`.

The manifest is small: 3.5 TB of pipeline output produced a **21 MB** TSV. Copy
it to your laptop and query it there if you prefer.

### The scan job

Create the output directory **before** submitting — SLURM opens the `--output`
file before your script runs, so an internal `mkdir` is too late and the job
fails instantly:

```bash
mkdir -p ~/size_scans
```

```bash
#!/bin/bash
#SBATCH --account=ddp195
#SBATCH --partition=ind-shared     # never `shared` — ddp195 cannot use it
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=16G
#SBATCH --time=4:00:00
#SBATCH --output=/home/%u/size_scans/scan_%j.out
#SBATCH --error=/home/%u/size_scans/scan_%j.err

TARGET="$1"
OUT="$HOME/size_scans/manifest_$(basename "$TARGET").tsv"
mkdir -p "$HOME/size_scans"

find "$TARGET" -printf '%s\t%b\t%T@\t%A@\t%C@\t%U\t%G\t%m\t%i\t%n\t%y\t%p\t%l\n' \
    > "$OUT"

echo "rows: $(wc -l < "$OUT")"
```

Two rules:

- **Manifests go on home or project storage, never `/tmp`.** `/tmp` is not shared
  between login and compute nodes, so you will not find the file afterwards.
- **One job per top-level directory.** A single slow tree shouldn't hold up the rest,
  and separate manifests are easier to re-run individually.

Validate before submitting — costs nothing, queues nothing:

```bash
sbatch --test-only scan.sh /expanse/projects/sebat1/some_dir
```

### Querying it

`duckdb` is not installed on Expanse. The simplest fix needs no environment, no
module, and no root — the CLI is one self-contained binary:

```bash
cd ~/size_scans
curl -sSL -O https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip
unzip -q duckdb_cli-linux-amd64.zip     # -> ./duckdb  (~21 MB download)
./duckdb --version                       # v1.5.5 as of 2026-08
```

Save the schema once as `schema.sql`, adjusting the path:

```sql
SET memory_limit='2GB';
SET threads=2;
SET preserve_insertion_order=false;

CREATE VIEW m AS
SELECT * FROM read_csv('manifest.tsv', delim='\t', header=false, quote='',
                       columns={
                         'size':'BIGINT','blocks':'BIGINT','mtime':'DOUBLE',
                         'atime':'DOUBLE','ctime':'DOUBLE','uid':'INT','gid':'INT',
                         'mode':'VARCHAR','inode':'BIGINT','nlink':'INT',
                         'ftype':'VARCHAR','path':'VARCHAR','linktarget':'VARCHAR'
                       });
```

Then run any query in this guide against it:

```bash
./duckdb -init schema.sql -c "SELECT count(*) FROM m;"
```

The three `SET` lines are not optional on a login node — see [Gotchas](#gotchas).

<details>
<summary>Alternative: the Python package, if you already keep an environment</summary>

`duckdb` and `polars` install cleanly into a micromamba env (see
[nextflow-expanse.md](nextflow-expanse.md) for installing micromamba itself):

```bash
micromamba create -n dataquery -c conda-forge python=3.12 duckdb polars
micromamba activate dataquery
```

```python
import duckdb

db = duckdb.connect()

# Login nodes cap per-user memory. DuckDB's defaults assume it owns the machine
# and will die with OutOfMemoryError on allocations as small as 32 MB. Set these
# three first -- without them the hardlink and dedup queries below fail.
db.execute("SET memory_limit='2GB'")
db.execute("SET threads=2")
db.execute("SET preserve_insertion_order=false")

SCHEMA_SQL = """
    CREATE VIEW m AS
    SELECT * FROM read_csv('__MANIFEST__', delim='\t', header=false, quote='',
                           columns={
                             'size':'BIGINT','blocks':'BIGINT','mtime':'DOUBLE',
                             'atime':'DOUBLE','ctime':'DOUBLE','uid':'INT','gid':'INT',
                             'mode':'VARCHAR','inode':'BIGINT','nlink':'INT',
                             'ftype':'VARCHAR','path':'VARCHAR','linktarget':'VARCHAR'
                           })
"""
db.execute(SCHEMA_SQL.replace("__MANIFEST__", "manifest.tsv"))
```

Three things that will bite you if you rewrite this snippet:

- **`read_csv`'s path cannot be a bound parameter** inside `CREATE VIEW`. Passing it
  as `?` raises `Binder Error: Unexpected prepared parameter`. Interpolate it.
- **Don't make it an f-string** — every brace of the `columns={...}` dict would have
  to be doubled. The `__MANIFEST__` placeholder avoids both traps.
- **`quote=''`** matters: paths containing `"` would otherwise be misparsed.

</details>

**What kind of data is it?** Compound extensions are handled so `.g.vcf.gz`
doesn't collapse into `.gz`:

```sql
SELECT lower(regexp_extract(path, '(\.[A-Za-z0-9]+)?(\.gz|\.bgz|\.zst)?$')) AS kind,
       count(*) AS n,
       sum(size)/1e12 AS TB
FROM m WHERE ftype = 'f'
GROUP BY 1 ORDER BY TB DESC LIMIT 25;
```

**How old is it?**

```sql
SELECT date_part('year', to_timestamp(mtime)) AS yr,
       sum(size)/1e12 AS TB, count(*) AS n
FROM m WHERE ftype = 'f'
GROUP BY 1 ORDER BY yr;
```

**Whose is it?** Build the uid→name map once (`getent passwd | cut -d: -f1,3`),
then join. The top level of `/expanse/projects/sebat1` holds directories owned by
former lab members — this is how you size them before asking for transfer.

**Big *and* old** — the archiving quadrant:

```sql
SELECT path, size/1e9 AS GB, to_timestamp(mtime)::DATE AS modified
FROM m
WHERE ftype = 'f' AND size > 10e9
  AND mtime < epoch(now() - INTERVAL 2 YEAR)
ORDER BY size DESC LIMIT 50;
```

**What would deleting it actually free?** The question people get wrong:

```sql
SELECT round(sum(size) FILTER (WHERE nlink = 1)/1e9, 2) AS truly_freed_GB,
       round(sum(size) FILTER (WHERE nlink > 1)/1e9, 2) AS hardlinked_GB
FROM m WHERE ftype = 'f';
```

Run against three levels of a real `nf_rare_spark_wes/work` tree:

```
truly_freed_GB   hardlinked_GB
      167.41          3540.09
```

**Of 3.7 TB, deleting that tree would free about 167 GB.** The other 95% is
hardlinked from the published results directory; removing one link just
decrements the count, and space comes back only when the last link goes. If you
plan a cleanup off `du` numbers you will badly overestimate what you recover.

A related trap: de-duplicating on `DISTINCT inode` *within* a manifest does **not**
fix this. On the same tree, naive and inode-deduplicated totals were identical
(3707.49 GB both ways), because each inode appears only once inside `work/` — its
sibling link lives outside the scanned tree. `nlink > 1` is the signal that
matters; `DISTINCT inode` only helps when both links are inside your manifest.

The same tree also held **21,678 symlinks and 8,673 directories** alongside 79,252
files, which is why the manifest drops `-type f` and records `%y` instead.

## 4. Archival and object storage

| Tier | How to inventory it | Cost |
|---|---|---|
| `sebat1` (non-S3 dirs) | `find -printf` scan job, section 3 | minutes–hours |
| `/expanse/projects/sebat1/s3/` | `aws s3api list-objects-v2` | **seconds** |
| `/expanse/lustre/projects` | `lfs quota`; `lfs find` for detail | instant / fast |
| Remote Globus collections | `globus ls -r --format json` | catalog only |

### The S3 shortcut

`s3://sebat/` and `/expanse/projects/sebat1/s3/` are the **same storage**. The S3
API will therefore inventory a large slice of the project space with no
filesystem walk at all:

```bash
aws --profile sebat s3api list-objects-v2 \
    --bucket sebat --prefix "igm_ccs_hifi_fastqs/" \
    --endpoint-url https://sebat.s3.sdsc.edu \
    --query 'Contents[].[Size,LastModified,StorageClass,Key]' --output text
```

Verified against the POSIX tree: **191 objects / 758,552,487,420 bytes on both
sides**, byte-for-byte identical — in 2.7 s versus minutes for `find`.

Limits worth knowing: the listing gives you size, mtime, storage class and key,
but **no uid, no permissions, no hardlink or symlink information**. Ownership
questions still need a `find` walk. Use `--prefix` per top-level folder;
listings paginate at 1,000 keys and the CLI handles that for you.

### Globus collections

`globus ls -r --format json` returns names and sizes from the collection's
catalog. It does **not** stage or transfer data, so it is safe to run against
archive-tier systems.

Useful collection IDs:

| Collection | ID |
|---|---|
| SDSC HPC - Expanse Lustre | `8735b734-00dc-4659-be0d-ff96beaff17b` |
| SDSC HPC - Projects | `46cad570-3f0d-4bfc-8ebc-ce2c13f13df7` |
| SDSC RDS Storage | `a9f6238a-1eb4-4bfb-a9b6-8bd6c4672c7f` |

The RDS collections require an extra consent step before they will list, and the
error is the same whether you lack consent or lack an allocation:

```
Missing required data_access consent
```

Fix it with an interactive browser login from your laptop:

```bash
globus session update a9f6238a-1eb4-4bfb-a9b6-8bd6c4672c7f
```

> **Status:** as of 2026-08-11 nobody has confirmed whether the lab holds data on
> SDSC RDS. If you run the consent step, please record the answer here.

## 5. Gotchas

- **Cache warmth dominates timings.** The same `find` took 118.7 s cold and 3.5 s
  warm. Never compare two tools across separate runs; alternate them and repeat.
- **`atime` is `relatime` on the NFS mounts**, so it updates at most ~once a day —
  good enough for "not read in two years", not for "read this morning". The Lustre
  mount shows no atime option at all; trust it less there.
- **Sparse files:** `%s` (apparent) can hugely exceed `%b × 512` (actual). Sum
  blocks when you care about real space.
- **Hardlinks double-count.** Deduplicate on `inode` before totalling.
- **Tabs in filenames** would corrupt the TSV. Check with
  `find "$TARGET" -name '*<TAB>*'` before trusting a parse.
- **`--partition=ind-shared`, always.** `ddp195` cannot use `shared`, and `shared`
  is the cluster default, so a missing `--partition` fails outright.
- **System `python3` on the login nodes is 3.6.** Anything newer than that
  (f-string `=`, `subprocess.run(capture_output=...)`) needs a micromamba env.
- **DuckDB OOMs on login nodes.** Per-user memory caps mean it fails on 32 MB
  allocations while claiming the whole node. Always `SET memory_limit`,
  `SET threads`, `SET preserve_insertion_order=false`, or run queries in a job.
- **Write scripts to a file and `scp` them.** Inline Python through
  `ssh host 'python3 -c "..."'` mangles quoting; it will bite you.

## Quick reference

```bash
# how much do I have left?          (instant)
lfs quota -h -u $USER /expanse/lustre/projects
df -Th /expanse/projects/sebat1

# how big is this one directory?    (~7 s per 3.5 TB, in a job)
~/.local/bin/diskus -j "$SLURM_CPUS_PER_TASK" "$DIR"

# what is in it?                    (one scan, then unlimited queries)
sbatch scan.sh "$DIR"

# what's in the S3-backed tree?     (seconds, no walk)
aws --profile sebat s3api list-objects-v2 --bucket sebat --prefix "PREFIX/" \
    --endpoint-url https://sebat.s3.sdsc.edu \
    --query 'Contents[].[Size,LastModified,Key]' --output text
```
