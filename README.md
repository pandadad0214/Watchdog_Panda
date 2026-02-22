<p align="center">
  <img src="Assets/Watchdog_Logo.jpg" width="220" />
</p>

<p align="center">

  <img src="https://img.shields.io/badge/Role-Resilience%20Guardian-orange" />
  <img src="https://img.shields.io/badge/Local‑First-green" />
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg" />
  <img src="https://img.shields.io/badge/Status-Active-success" />

</p>

---

# 🛡️ Watchdog Panda  
### Process Monitoring • Auto‑Restart • Local‑First Uptime Guardian

Watchdog Panda is the **sentinel node** of the Panda Federation — a lightweight, reliable, local‑first watchdog designed to keep critical AI processes alive.

He doesn’t talk.  
He doesn’t emote.  
He **watches**, **detects**, and **acts**.

If a process crashes, Watchdog Panda brings it back.  
If a service hangs, he restarts it.  
If Spirit Panda or Steel Panda go down, he’s the one who stands them back up.

---

# 🌟 Features

### 🛡️ **Process Monitoring**
- Watches any target process by name  
- Detects crashes or unexpected exits  
- Logs every event with timestamps  

### 🔁 **Auto‑Restart Logic**
- Executes a restart command when needed  
- Works with any script or service  
- Fully Termux‑compatible  

### 📜 **Event Logging**
- Writes to `watchdog.log`  
- Tracks restarts, failures, and uptime events  

### ⚙️ **Configurable Behavior**
- Change target process  
- Adjust check interval  
- Customize restart command  
- Extend with hooks (notifications, webhooks, etc.)  

### 📱 **Mobile‑Friendly**
- Designed for Android + Termux  
- Lightweight and battery‑aware  
- Zero external dependencies  

---

# 🏗 Architecture Overview

See `docs/index.md` for full details.

### Core Components:
- `watchdog.sh` — main watchdog loop  
- `assets/` — Watchdog Panda crest  
- `docs/` — documentation index  
- `CHANGELOG.md` — version history  
- `LICENSE` — MIT license  

Watchdog Panda is intentionally minimal — reliability through simplicity.

---

# 🚀 Quickstart

```bash
git clone https://github.com/pandadad0214/watchdog-panda.git
cd watchdog-panda
chmod +x watchdog.sh
./watchdog.sh
