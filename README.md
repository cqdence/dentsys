# Dentsys ZFS Standardized Snapshot Tool

**Master Documentation**

Dentsys is a customized, internal fork of **pyznap** designed to standardize ZFS backups across all client servers. It enforces strict naming conventions, file paths, and retention policies to ensure homogeneity across our infrastructure.

---

## 🚨 Critical Dentsys Customizations

**Read this before debugging.**

### 1. Naming Convention
Snapshots are strictly named using the format: `dentsys_YYYY-MM-DD_HH:MM:SS_TYPE`.
* **Example:** `dentsys_2025-11-27_12:00:00_hourly`
* **Why:** The cleaning logic parses the name by splitting on underscores `_`. The prefix `dentsys` is **required** for the tool to recognize (and delete) old snapshots.

### 2. Hardcoded Paths (Stability)
The Python code explicitly calls `/usr/sbin/zfs` and `/usr/bin/ssh`.
* **Why:** This prevents "Command Not Found" errors when running via Cron, which often has a stripped-down `$PATH`.

### 3. Config Location
Configuration is stored in `/etc/dentsys/dentsys.conf`.
* *Note:* Legacy pyznap configs in `/etc/pyznap/` are ignored.

---

## 🚀 Installation & Deployment

### 1. New Server Setup (The "One-Liner")
For a fresh server, run this command as root. This script handles dependencies (pipx, lz4, zstd), installs the software, auto-detects the ZFS pool name (e.g., `sas5`), intelligently finds datasets to snapshot, writes the config, and sets up Cron.

```bash
curl -sL https://raw.githubusercontent.com/cqdence/dentsys/master/install.sh | bash
```

**What the installer does:**
1. ✅ Installs dependencies (pipx, git, lz4, zstd, zfsutils-linux)
2. ✅ Installs Dentsys via pipx from GitHub
3. ✅ Auto-detects your ZFS pool (excluding boot pools like rpool/bpool)
4. ✅ **Intelligently detects the best dataset** to snapshot:
   - Looks for `{pool}/data` (common Proxmox pattern)
   - Falls back to `{pool}/vm-data` or other common structures
   - Uses pool root if no subdatasets found
5. ✅ Creates configuration file at `/etc/dentsys/dentsys.conf`
6. ✅ Sets up log rotation at `/var/log/dentsys.log` (weekly, 12 weeks retention)
7. ✅ Installs cron jobs (snapshots every 15 min, backups daily at midnight)
8. ✅ Validates the installation and shows configuration summary

**Manual dataset selection:**
If the auto-detection picks the wrong dataset, specify it manually:

```bash
DENTSYS_DATASET=tank/mydata curl -sL https://raw.githubusercontent.com/cqdence/dentsys/master/install.sh | bash
```

**Private repository installation:**
If the repository is private, use a GitHub Personal Access Token:

```bash
# 1. Create token at: https://github.com/settings/tokens
#    Required scope: "repo" (full control of private repositories)

# 2. Export token and run installer
export GITHUB_TOKEN="ghp_your_token_here"
curl -sL -H "Authorization: token ${GITHUB_TOKEN}" \
  https://raw.githubusercontent.com/cqdence/dentsys/master/install.sh | bash
```

The token is only used during installation and is not stored on the server.

**Re-running the installer:**
The installer is idempotent and can be safely re-run. It will:
- Update dentsys to the latest version
- Replace cron jobs (removes duplicates automatically)
- Regenerate configuration (backs up existing to `/etc/dentsys/dentsys.conf.bak` if modified)

### 2. Legacy Migration (Upgrading from Pyznap)
If a server is running the old pyznap version, you **must** clean it up to prevent scheduling conflicts.

```bash
# 1. Remove old Cron jobs
crontab -l | grep -v "pyznap" | crontab -

# 2. Uninstall old package
pipx uninstall pyznap 2>/dev/null || pip3 uninstall -y pyznap

# 3. Remove old config directory
rm -rf /etc/pyznap

# 4. Run the new installer
curl -sL https://raw.githubusercontent.com/cqdence/dentsys/master/install.sh | bash
```

---

## ⚙️ Configuration Standards

### Auto-Generated Config
The installer generates `/etc/dentsys/dentsys.conf` using a master template. It automatically populates:
* `{{HOSTNAME}}`: The server's hostname.
* `{{POOL}}`: The active ZFS data pool (e.g., `sas5`, `nvme`).

### The Dentsys Retention Policy
All servers adhere to this standard policy:

| Type | Count | Duration |
| :--- | :--- | :--- |
| **Frequent** | 4 | Last 60 mins (15m intervals) |
| **Hourly** | 24 | Last 24 hours |
| **Daily** | 7 | Last 7 days |
| **Weekly** | 4 | Last 4 weeks |
| **Monthly** | 6 | Last 6 months |
| **Yearly** | 1 | Last 1 year |

### Standard Config Template (`dentsys.conf`)

```ini
[{{POOL}}/data]
# --- Retention ---
frequent = 4
hourly = 24
daily = 7
weekly = 4
monthly = 6
yearly = 1

# --- Actions ---
snap = yes
clean = yes

# --- Destinations ---
# Uncomment and update the IP for the specific office/cloud target
# dest = ssh:22:root@192.168.X.X:backup/{{HOSTNAME}}
# dest_keys = /root/.ssh/id_rsa_onsite
compress = lz4
```

---

## 🕒 Automation (Cron)

The tool runs automatically via the root Crontab.
**Log Location:** `/var/log/dentsys.log`

```bash
# 1. Snapshots & Cleanup (Every 15 minutes)
*/15 * * * * dentsys snap >> /var/log/dentsys.log 2>&1

# 2. Send to Remote Backup (Daily at Midnight)
0 0 * * * dentsys send >> /var/log/dentsys.log 2>&1
```

*Note: The installer automatically adds `PATH=/usr/sbin:/usr/bin:/sbin:/bin` to the top of the crontab as a fail-safe.*

---

## 🛠 Manual Usage & CLI

You can run commands manually for testing or force-runs.

**Check Version:**
```bash
dentsys --version
```

**Take Snapshots (Manual Run):**
```bash
dentsys snap --verbose
```

**Send Backups (Manual Run):**
```bash
dentsys send --verbose
```

**Cleanup Only:**
```bash
dentsys snap --clean --verbose
```

---

## 🔧 Troubleshooting & Maintenance

### Common Issues

#### 1. "Command not found: dentsys"
* **Cause:** pipx installs binaries to `/root/.local/bin`, which might not be in the global `$PATH`.
* **Fix:** The installer creates a symlink, but you can recreate it:
    ```bash
    ln -sf /root/.local/bin/dentsys /usr/local/bin/dentsys
    ```

#### 2. Snapshots are not being deleted (Disk Full)
* **Cause:** The tool only deletes snapshots starting with `dentsys_`. If you have manual snapshots or old `pyznap_` snapshots, it ignores them safely.
* **Fix:** Check the snapshot names:
    ```bash
    zfs list -t snapshot
    ```

#### 3. "ZFS command not found" in logs
* **Cause:** The server has ZFS installed in a non-standard location (not `/usr/sbin/zfs`).
* **Fix:** Create a symlink so the tool can find it:
    ```bash
    ln -s /path/to/actual/zfs /usr/sbin/zfs
    ```

#### 4. "Dataset does not exist" errors
* **Cause:** The auto-detected dataset was incorrect, or the dataset was deleted after installation.
* **Fix:** Edit `/etc/dentsys/dentsys.conf` and update the section header to match your actual dataset:
    ```bash
    # Change this:
    [rpool/data]

    # To match your actual dataset:
    [tank/vm-storage]
    ```
* **Verify dataset exists:**
    ```bash
    zfs list
    ```

#### 5. Duplicate cron jobs running
* **Cause:** Older versions had a bug in cron deduplication.
* **Fix:** Clean up crontab and re-run installer:
    ```bash
    crontab -e
    # Remove duplicate dentsys lines, save and exit
    # Then re-run installer to add clean jobs
    curl -sL https://raw.githubusercontent.com/cqdence/dentsys/master/install.sh | bash
    ```

#### 6. Installation fails with "Failed to download configuration"
* **Cause:** Network issues or GitHub is unavailable.
* **Fix:** Check internet connectivity and retry:
    ```bash
    curl -I https://raw.githubusercontent.com/cqdence/dentsys/master/pyznap/dentsys.conf.template
    ```

### Monitoring and Logs

**View recent activity:**
```bash
tail -f /var/log/dentsys.log
```

**Check snapshot status:**
```bash
zfs list -t snapshot | grep dentsys
```

**View current configuration:**
```bash
cat /etc/dentsys/dentsys.conf
```

**Check cron schedule:**
```bash
crontab -l | grep dentsys
```

**Manually test snapshot creation:**
```bash
dentsys snap --verbose
```

---

## Updating the Tool (Developer Guide)

If you modify the Python code in this repository:

1.  **Commit Changes:** Push your edits to the master branch on GitHub.
2.  **Deploy Update:** Run the install command with `--force` on the client servers.

```bash
pipx install --force git+https://github.com/cqdence/dentsys.git
```

### Repository Structure

* `install.sh`: The automation script used by curl.
* `dentsys.conf.template`: The source configuration file with `{{VARIABLES}}`.
* `setup.py`: Defines the package metadata and entry point (`dentsys`).
* `pyznap/`: The core Python source code.
    * `pyzfs.py`: Contains hardcoded ZFS paths.
    * `ssh.py`: Contains hardcoded SSH paths.
    * `take.py` / `clean.py`: Contains naming convention logic.
    * `main.py`: Contains config directory logic.
