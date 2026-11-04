<p align="center">
  <img src="Assets/Watchdog_Logo.jpg" width="200" />
</p>

<h1 align="center">🛡️ Watchdog Panda</h1>
<h3 align="center">The Vigilant Sentinel of the Panda Federation</h3>

<p align="center">
  <img src="https://img.shields.io/github/stars/pandadad0214/watchdog_panda?style=flat&color=7b2ff7" />
  <img src="https://img.shields.io/github/forks/pandadad0214/watchdog_panda?style=flat&color=9d4bff" />
  <img src="https://img.shields.io/github/license/pandadad0214/watchdog_panda?style=flat&color=5f1bd1" />
  <img src="https://img.shields.io/github/last-commit/pandadad0214/watchdog_panda?style=flat&color=6a00ff" />
</p>

<p align="center"><b>A tiny watchdog script: if a process stops, Watchdog Panda restarts it and logs what happened. Linux, macOS and Termux.</b></p>

<p align="center">
  <a href="https://github.com/pandadad0214/Watchdog_Panda/releases/latest"><img src="https://img.shields.io/github/v/release/pandadad0214/Watchdog_Panda?label=latest%20release" /></a>
  <a href="https://github.com/pandadad0214/Watchdog_Panda/actions/workflows/ci.yml"><img src="https://github.com/pandadad0214/Watchdog_Panda/actions/workflows/ci.yml/badge.svg" /></a>
</p>

<p align="center"><b><a href="https://github.com/pandadad0214/Watchdog_Panda/releases/latest">⬇ Download the latest Release</a></b></p>

---

# 🚀 Install / Use

One command (installs into `~/watchdog-panda`):

```bash
curl -fsSL https://github.com/pandadad0214/Watchdog_Panda/releases/latest/download/install.sh | bash
```

Then tell it what to watch and how to restart it:

```bash
cd ~/watchdog-panda
TARGET_PROCESS="my-app" START_COMMAND="nohup ./my-app.sh &" bash Watchdog.sh
```

| Setting | Default | Meaning |
|---|---|---|
| `TARGET_PROCESS` | `spirit-panda` | Text to match in the running process list (`pgrep -f`) |
| `START_COMMAND` | `./start.sh` | Command that restarts it (end with `&` so the watchdog keeps watching) |
| `CHECK_INTERVAL` | `5` | Seconds between checks |
| `LOG_FILE` | `watchdog.log` | Where events are written |

Stop it with Ctrl+C. Prefer a manual download? Grab `watchdog-panda.tar.gz` from the [latest Release](https://github.com/pandadad0214/Watchdog_Panda/releases/latest) and check it against `SHA256SUMS.txt`.

---

# 🧭 Overview

**Watchdog Panda** is the uptime guardian of the Panda Federation — a lightweight, local‑first monitoring agent that keeps your system, services, and AI agents alive, responsive, and stable.

It watches.  
It reports.  
It protects.

Watchdog Panda ensures that Spirit Panda, Steel Panda, and future Federation agents always know the state of the system.

---

# 🧩 Role in the Panda Federation

```
Spirit Panda  ← receives status + insights
     ▲
     │
Watchdog Panda  ← monitors uptime, processes, agents
     │
     ▼
Steel Panda  ← executes tasks + corrective actions
```

Watchdog Panda is the **first line of defense**, ensuring:

- Spirit Panda always has accurate system awareness  
- Steel Panda only acts when necessary  
- The Federation remains stable, predictable, and sovereign  

---

# ⚙️ Features

- Local‑first monitoring loop  
- Configurable heartbeat intervals  
- Process/service uptime checks  
- Failure detection and escalation  
- Optional logging and event timeline  
- Integration hooks for Spirit Panda  
- Trigger hooks for Steel Panda  
- Lightweight, modular architecture  

---

# 🔄 How It Works

### **1. Heartbeat Loop**  
A timed loop checks:

- processes  
- services  
- agents  
- system metrics (optional)  

### **2. Failure Detection**  
If something stops responding, Watchdog Panda:

- logs the event  
- notifies Spirit Panda  
- optionally triggers Steel Panda  

### **3. Recovery Actions**  
Steel Panda may:

- restart a service  
- run a script  
- perform cleanup  
- escalate to the user  

---

# 🛠 For developers

```
Watchdog_Panda/
├── Watchdog.sh        # the watchdog loop
├── install.sh         # one-command installer used by the Release
├── Assets/            # logo
├── Index.md           # documentation
├── Documents/
├── CHANGELOG / LICENSE / CONTRIBUTING / CODE_OF_CONDUCT
```

Run from a clone: `git clone https://github.com/pandadad0214/Watchdog_Panda.git && cd Watchdog_Panda && bash Watchdog.sh`

Releases are automatic: add a line to `Changelog.md`, then push a `vX.Y.Z` tag. `.github/workflows/release.yml` packages `watchdog-panda.tar.gz`, `install.sh` and `SHA256SUMS.txt` and publishes the GitHub Release.

---

# 🗺️ Roadmap

### **Planned Features**
- A `config/watchdog.yaml` file for watching several services at once  
- Multi‑agent heartbeat mesh  
- Federation‑wide status dashboard  
- Local‑first event timeline  
- Configurable escalation levels  
- Optional encrypted logs  
- Integration with PandaMom and PandaLily  
- Auto‑recovery routines  

---

# 📚 Documentation

Full documentation: [`Index.md`](Index.md)

---

# 🪶 Panda Oath

**Build slow.  
Build steady.  
Build sovereign.**

Watchdog Panda stands guard so the Federation may thrive.

---

# 📜 License

This project is licensed under the **MIT License**.  
See the `LICENSE` file for details.
