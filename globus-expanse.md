# Globus on Expanse

Setting up Globus for file transfers on SDSC Expanse.

## Why Globus?

- Transfers resume automatically if interrupted
- Much faster than scp/rsync for large files
- Required for some data sources (e.g., SFARI)
- Web interface or CLI

## Setup

### 1. Install Globus CLI

```bash
pip install --user globus-cli
# or
micromamba install globus-cli -c conda-forge
```

### 2. Authenticate

```bash
globus login
```

This opens a browser link. Complete authentication, then the CLI works.

### 3. Install Globus Connect Personal (optional)

For accessing your Expanse directories as a personal endpoint:

```bash
cd ~
wget https://downloads.globus.org/globus-connect-personal/linux/stable/globusconnectpersonal-latest.tgz
tar xzf globusconnectpersonal-latest.tgz
cd globusconnectpersonal-*
./globusconnectpersonal -setup
```

Follow the prompts to name your endpoint.

### 4. Configure accessible paths

Edit `~/.globusonline/lta/config-paths` to control what Globus can access:

```
~/,0,1
/expanse/projects/sebat1/,0,1
/expanse/lustre/projects/ddp195/,0,1
```

Format: `path,sharing(0=no),read-write(1=yes)`

### 5. Start Globus Connect Personal

```bash
./globusconnectpersonal -start &
```

To stop:
```bash
./globusconnectpersonal -stop
```

## Common Endpoints

| Endpoint | ID | Description |
|----------|-----|-------------|
| SFARI Collections | `98f73ff6-b423-11ec-bae0-cd8db799a66a` | SFARI data (SPARK, SSC) |
| SDSC Expanse | `36530efa-a1e3-11e9-9766-0a5f1a4b9a17` | Official Expanse endpoint |
| Your personal | Run `globus endpoint local-id` | Your GCP endpoint |

## CLI Commands

### Check authentication

```bash
globus whoami
```

### List endpoints

```bash
# Search for endpoints
globus endpoint search "expanse"

# Your endpoints
globus endpoint my-list
```

### Browse files

```bash
# List directory on an endpoint
globus ls ENDPOINT_ID:/path/to/directory
```

### Transfer files

```bash
# Single file
globus transfer SOURCE_ENDPOINT:/path/file DEST_ENDPOINT:/path/file

# Directory (recursive)
globus transfer SOURCE_ENDPOINT:/path/dir DEST_ENDPOINT:/path/dir --recursive

# Batch transfer
globus transfer SOURCE_ENDPOINT DEST_ENDPOINT --batch < files.txt
```

Where `files.txt` contains:
```
/source/path1 /dest/path1
/source/path2 /dest/path2
```

### Check transfer status

```bash
# List recent tasks
globus task list

# Details on specific task
globus task show TASK_ID

# Wait for task to complete
globus task wait TASK_ID
```

### Cancel transfer

```bash
globus task cancel TASK_ID
```

## Example: Download SFARI Data

```bash
# SFARI endpoint
SFARI="98f73ff6-b423-11ec-bae0-cd8db799a66a"

# Your personal endpoint (get ID with: globus endpoint local-id)
MINE="your-endpoint-id-here"

# List available SPARK data
globus ls $SFARI:/SPARK/pub/

# Transfer SPARK iWES data
globus transfer $SFARI:/SPARK/pub/iWES_v3/ $MINE:/expanse/projects/sebat1/$USER/spark_iwes/ --recursive
```

## Tips

### Sync mode (only transfer new/changed files)

```bash
globus transfer SOURCE DEST --sync-level checksum --recursive
```

Sync levels:
- `exists` - Skip if file exists at destination
- `size` - Skip if same size
- `mtime` - Skip if same modification time
- `checksum` - Skip if same checksum (slowest but safest)

### Email notification when done

```bash
globus transfer SOURCE DEST --notify on
```

### Label your transfers

```bash
globus transfer SOURCE DEST --label "SPARK WES download"
```

Makes it easier to track in `globus task list`.

## Troubleshooting

### "Permission denied"

- Check `~/.globusonline/lta/config-paths` includes the path
- Restart GCP after editing: `./globusconnectpersonal -stop && ./globusconnectpersonal -start &`

### Transfer stuck at 0%

- Large directories take time to index before transfer starts
- Check task status: `globus task show TASK_ID`

### GCP not running

```bash
# Check if running
ps aux | grep globusconnect

# Start it
cd ~/globusconnectpersonal-*
./globusconnectpersonal -start &
```
