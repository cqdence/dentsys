# Dentsys ZFS Snapshot Tool

**Dentsys** is our standardized internal tool for managing ZFS snapshots and backups across client servers.

It has been customized to enforce:
* **Standard Naming:** Snapshots are named `dentsys_DATE_TIME_TYPE`.
* **Hardcoded Stability:** Uses absolute paths (`/usr/sbin/zfs`) to prevent Cron failures on Proxmox.
* **Internal Compliance:** Simplifies configuration for our specific backup topology.

---

## 🛠 Installation

We use `pipx` to install this tool in an isolated environment. This prevents conflicts with the Proxmox system Python.

### Standard Install (Proxmox 7/8)
Run this on any client server (requires root):

```bash
apt-get update && apt-get install -y pipx git lz4 zstd
pipx ensurepath
pipx install --force git+[https://github.com/cqdence/dentsys.git](https://github.com/cqdence/dentsys.git)