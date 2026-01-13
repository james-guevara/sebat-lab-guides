# SSH Config for SDSC Clusters

SSH multiplexing lets you authenticate once (password + TOTP), then all subsequent connections reuse that session automatically.

## Why This Matters

- SDSC clusters require TOTP (time-based one-time passwords)
- Without multiplexing: every SSH command prompts for password + TOTP
- With multiplexing: authenticate once, everything else piggybacks

This is especially useful for:
- Running multiple terminals to the cluster
- Using tools like Claude Code that SSH on your behalf
- Scripts that make multiple SSH connections

## Setup

Add this to `~/.ssh/config` (create the file if it doesn't exist).

Replace `YOUR_USERNAME` with your SDSC username.

```bash
# Global defaults - keep connections alive
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3

# =============================================================================
# EXPANSE
# =============================================================================

# Primary connection (authenticate here first)
Host expanse
    HostName login.expanse.sdsc.edu
    User YOUR_USERNAME
    ControlPath ~/.ssh/expanse-control
    ControlMaster auto
    ControlPersist 12h

# Login node aliases (same socket)
Host expanse01
    HostName login01.expanse.sdsc.edu
    User YOUR_USERNAME
    ControlPath ~/.ssh/expanse-control
    ControlMaster auto
    ControlPersist 12h

Host expanse02
    HostName login02.expanse.sdsc.edu
    User YOUR_USERNAME
    ControlPath ~/.ssh/expanse-control
    ControlMaster auto
    ControlPersist 12h

# Compute nodes via jump host (for interactive jobs)
Host exp-*
    User YOUR_USERNAME
    ProxyJump expanse

# =============================================================================
# TSCC
# =============================================================================

Host tscc
    HostName login.tscc.sdsc.edu
    User YOUR_USERNAME
    ControlPath ~/.ssh/tscc-control
    ControlMaster auto
    ControlPersist 12h

Host tscc1
    HostName login1.tscc.sdsc.edu
    User YOUR_USERNAME
    ControlPath ~/.ssh/tscc-control
    ControlMaster auto
    ControlPersist 12h

Host tscc2
    HostName login2.tscc.sdsc.edu
    User YOUR_USERNAME
    ControlPath ~/.ssh/tscc-control
    ControlMaster auto
    ControlPersist 12h
```

## What Each Setting Does

| Setting | Purpose |
|---------|---------|
| `ControlPath ~/.ssh/expanse-control` | Socket file for multiplexed connections |
| `ControlMaster auto` | First connection becomes master, others reuse it |
| `ControlPersist 12h` | Keep socket alive 12 hours after last disconnect |
| `ServerAliveInterval 60` | Send keepalive every 60 seconds (prevents timeout) |
| `ProxyJump expanse` | For compute nodes: automatically hop through login node |

## Usage

### Basic workflow

1. Open a terminal and connect:
   ```bash
   ssh expanse
   # Enter password + TOTP code
   ```

2. Leave it open (or close it - socket persists for 12 hours)

3. Open another terminal - no password needed:
   ```bash
   ssh expanse  # Instant connection!
   ```

### Connecting to compute nodes

If you have an interactive job on a compute node:
```bash
ssh exp-15-01  # Automatically jumps through expanse login
```

## Troubleshooting

### Socket corrupted (repeated password prompts or ssh_askpass errors)

```bash
# Kill the socket
ssh -O exit expanse

# Reconnect fresh
ssh expanse
```

### Check if socket exists

```bash
ls -la ~/.ssh/expanse-control
```

### Force a fresh master connection

```bash
ssh -O exit expanse && ssh expanse
```

### Connection times out

The `ServerAliveInterval 60` setting should prevent this, but if connections still drop:

```bash
# In ~/.ssh/config, try shorter interval:
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 5
```

## For Claude Code Users

1. SSH to expanse manually first (in a separate terminal)
2. Keep that terminal open
3. Now Claude Code can SSH to expanse without prompts

If Claude Code starts showing `ssh_askpass` errors, the socket is corrupted - run `ssh -O exit expanse` and reconnect.
