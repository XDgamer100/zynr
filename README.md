# Zynr.Cloud v5.1.0 — All-in-One Server Manager

One command to manage, secure, and optimize your VPS.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/XDgamer100/zynr/main/install.sh)
```

> ⚠️ Replace `XDgamer100` with your GitHub username after forking.

---

## 🖥️ Supported Systems

| OS | Version |
|----|---------|
| Ubuntu | 22.04, 24.04 |
| Debian | 12, 13 |

---

## 📦 Categories

### 🚀 [1] Pterodactyl & Wings
Install, update, and manage Pterodactyl Panel + Wings daemon.

- Install Panel / Wings / Both
- Update Panel / Wings
- User Management
- Blueprint Framework Manager
- Eggs Manager (200+ game server eggs)
- 🎨 Themes & Addons — **HyperV1 Premium Theme**
- Status & Logs
- Uninstall

> 💎 HyperV1 Theme requires a license. Purchase at: 👉 discord.gg/99XJuwpV9w → open a ticket

---

### 🖥️ [2] Control Panels
Web-based server management and billing panels.

- **Cockpit** — browser-based server manager (port 9090)
- **Paymenter** — open-source billing panel
- **FOSSBilling** — free billing & client automation
- **cPanel** — traditional hosting panel
- **Virtualizor** — VPS control panel
- **VirtFusion** — VPS platform

---

### 🛡️ [3] Security & DDoS Protection
Minecraft-aware firewall and intrusion prevention suite.

- UFW Firewall (rate limiting, port rules)
- Fail2Ban (brute-force, Minecraft login flood jails)
- NFTables stateful firewall (dynamic blocked_ips set)
- CrowdSec collaborative threat intelligence
- IPSet blocklists (Firehol Level-1)
- DDoS Auto-Monitor Daemon (auto-bans floods via ipset)
- Kernel sysctl hardening
- Nginx rate limiting

---

### ☁️ [4] Cloud Tools
Enable root SSH on cloud VPS providers that block it by default.

| Provider | Method |
|----------|--------|
| Azure | Patches sshd_config.d/50-cloud-init.conf, removes AllowUsers |
| GCP | Disables google-guest-agent to prevent config reset |
| AWS | Patches sshd_config, fixes default user |
| Hetzner / Vultr / DigitalOcean | Standard sshd_config patch |

---

### ⚡ [5] System Optimizer
Kernel-level performance tuning for VPS & game servers.

| Module | Covers |
|--------|--------|
| cpu.sh | Governor, Intel pstate/turbo/HWP/C-states, AMD pstate/boost, IRQ |
| memory.sh | ZRAM, ZSWAP, Huge Pages (2MB/1GB), VM sysctl |
| kernel.sh | BBR+CAKE network, I/O scheduler, full sysctl, KSM, OOM, Mitigations |
| tools.sh | Auto full-optimize, live stats, restore defaults |

---

### 🖥️ [6] VPS Manager *(NEW in v5.1.0)*
Full Proxmox-based VPS reselling toolkit — provision, manage, backup, and monitor.

| # | Feature | Description |
|---|---------|-------------|
| 1 | 🔐 Server Setup | Full hardening: update, vpsadmin user, SSH hardening, fail2ban, UFW, auto-updates |
| 2 | 📦 Template Builder | Download + create cloud-init templates: Ubuntu 22/24, Debian 12, Rocky Linux 9 |
| 3 | 🚀 Provision VPS | Interactive — pick plan, IP, OS → VM ready in ~60 seconds |
| 4 | 📋 List All VMs | Status, IP, RAM per VM |
| 5 | 🗑️ Delete VPS | Stop + destroy + purge storage |
| 6 | 📊 Live Resources | RAM, CPU, ZFS pool, per-VM usage, disk usage |
| 7 | 💾 Backup Manager | PBS install, snapshots, vzdump, restore, auto-cron |
| 8 | ❤️ Health Check | Full diagnostics + optional email alert + daily cron |

**VPS Plans (built-in pricing):**

| Plan | RAM | Disk | Price |
|------|-----|------|-------|
| XS | 2GB | 50GB | ₹199/mo |
| S | 4GB | 80GB | ₹249/mo |
| M | 8GB | 100GB | ₹419/mo |
| L | 16GB | 150GB | ₹589/mo |
| XL | 24GB | 200GB | ₹919/mo |
| XXL | 32GB | 300GB | ₹1,259/mo |
| 2XL | 48GB | 350GB | ₹1,599/mo |
| 3XL | 64GB | 400GB | ₹2,099/mo |

---

## 📁 Repo Structure

```
zynr/
├── install.sh              ← ONE command entry point
├── core.sh                 ← Shared colours, helpers, detection
│
├── ptero/                  ← Pterodactyl & Wings
│   ├── menu.sh
│   ├── panel.sh
│   ├── users.sh
│   ├── blueprint.sh
│   ├── eggs.sh             ← 200+ game eggs
│   ├── themes.sh           ← HyperV1 theme installer
│   ├── status.sh
│   └── uninstall.sh
│
├── panels/                 ← Control Panels
│   ├── menu.sh
│   ├── cockpit.sh
│   └── extras.sh
│
├── security/               ← DDoS & Firewall
│   ├── menu.sh
│   └── ddos.sh
│
├── cloud/                  ← Cloud Root Enabler
│   ├── menu.sh
│   └── cloud.sh
│
├── optimize/               ← System Optimizer
│   ├── menu.sh
│   ├── helpers.sh
│   ├── cpu.sh
│   ├── memory.sh
│   ├── kernel.sh
│   └── tools.sh
│
├── vps/                    ← VPS Manager (NEW v5.1.0)
│   ├── menu.sh             ← [6] menu navigation
│   └── vps.sh              ← setup · templates · provision · list · delete · resources
│
├── backup/                 ← Backup Manager (NEW v5.1.0)
│   └── backup.sh           ← PBS · snapshots · vzdump · restore · cron
│
└── monitoring/             ← Health Monitoring (NEW v5.1.0)
    └── health.sh           ← full diagnostics + email alerts
```

---

## 🚀 How to Push to GitHub

```bash
# 1. Create a new repo at github.com named "zynr" (public, no README)
# 2. On your machine:
git init
git add .
git commit -m "Zynr.Cloud v5.1.0 - All-in-One Server Manager + VPS Manager"
git branch -M main
git remote add origin https://github.com/XDgamer100/zynr.git
git push -u origin main
# 3. Edit install.sh line 13 — replace XDgamer100 with your GitHub username
```

---

## 💎 HyperV1 License

HyperV1 is a premium Pterodactyl theme. To use it:
1. Install via Zynr.Cloud → Pterodactyl → Themes & Addons → HyperV1
2. Join Discord: discord.gg/99XJuwpV9w
3. Open a ticket and purchase your license
4. Staff will activate it for you

---

## ⚠️ Disclaimer

- Run as root only
- Test on a staging server before production
- CPU mitigation options (Spectre/Meltdown) carry security risk — read warnings carefully
- Cloud root enabler modifies SSH config — ensure you have console/VNC access as a backup

---

Built with ❤️ by Zynr.Cloud · discord.gg/99XJuwpV9w
