<p align="center">
  <img src="Assets/Watchdog_Logo.jpg" width="200" />
</p>

<h1 align="center">🛡️ Watchdog Panda</h1>
<h3 align="center">A local process watchdog</h3>

<p align="center">
  <img src="https://img.shields.io/github/stars/pandadad0214/watchdog_panda?style=flat&color=7b2ff7" />
  <img src="https://img.shields.io/github/forks/pandadad0214/watchdog_panda?style=flat&color=9d4bff" />
  <img src="https://img.shields.io/github/license/pandadad0214/watchdog_panda?style=flat&color=5f1bd1" />
  <img src="https://img.shields.io/github/last-commit/pandadad0214/watchdog_panda?style=flat&color=6a00ff" />
</p>

<p align="center"><b>If a process disappears, Watchdog Panda restarts it, waits longer each time it fails, and can run a shell command when that happens. Linux, macOS, and Termux. Bash only.</b></p>

<p align="center">
  <a href="https://github.com/pandadad0214/Watchdog_Panda/releases/latest"><img src="https://img.shields.io/github/v/release/pandadad0214/Watchdog_Panda?label=latest%20release" /></a>
  <a href="https://github.com/pandadad0214/Watchdog_Panda/actions/workflows/ci.yml"><img src="https://github.com/pandadad0214/Watchdog_Panda/actions/workflows/ci.yml/badge.svg" /></a>
</p>

---

# 🚀 Install / Use

One process, from a clone of this repo (version 0.2.0):

```bash
git clone https://github.com/pandadad0214/Watchdog_Panda.git
cd Watchdog_Panda
TARGET_PROCESS="my-app" START_COMMAND="nohup ./my-app.sh &" bash Watchdog.sh
```

The curl installer downloads the **latest tagged Release**. Clone the repo to run 0.2.0 before a `v0.2.0` tag exists. After that tag is pushed, this also works:

```bash
curl -fsSL https://github.com/pandadad0214/Watchdog_Panda/releases/latest/download/install.sh | bash
cd ~/watchdog-panda
TARGET_PROCESS="my-app" START_COMMAND="nohup ./my-app.sh &" bash Watchdog.sh
```

Stop it with Ctrl+C. Events go to `watchdog.log`.

| Setting | Default | Meaning |
|---|---|---|
| `TARGET_PROCESS` | `spirit-panda` | Pattern passed to `pgrep -f` |
| `START_COMMAND` | `./start.sh` | Shell command that restarts it. It must return; end with `&` so Watchdog keeps looping |
| `CHECK_INTERVAL` | `5` | Seconds between checks |
| `LOG_FILE` | `watchdog.log` | Where events are written |
| `MAX_RESTARTS` | `5` | Give up after this many restart attempts |
| `BACKOFF_INITIAL` | `2` | Seconds to wait after the first restart. The wait doubles each attempt |
| `BACKOFF_MAX` | `60` | Cap on that wait |
| `COOLDOWN` | `0` | After giving up, try again after this many seconds. `0` stays quiet until the process is seen running |
| `ON_FAILURE` | empty | Extra shell command after each restart attempt, and once when giving up |

These variables are the whole configuration when no config file is present. That is the same single-process mode as 0.1.0, plus the restart cap, backoff, and hook.

Prefer a manual download of a tagged Release? Grab `watchdog-panda.tar.gz` from the [latest Release](https://github.com/pandadad0214/Watchdog_Panda/releases/latest) and check it against `SHA256SUMS.txt`.

---

# Several services

Copy [`config/watchdog.example.yaml`](config/watchdog.example.yaml) and edit it. Watchdog loads the first file it finds:

1. `$WATCHDOG_CONFIG`
2. `./config/watchdog.yaml`
3. `./watchdog.yaml`

```bash
cp config/watchdog.example.yaml config/watchdog.yaml
bash Watchdog.sh
```

```yaml
check_interval: 5
log_file: watchdog.log
max_restarts: 5
backoff_initial: 2
backoff_max: 60
cooldown: 0

services:
  - name: spirit-panda
    process: spirit-panda
    start: 'nohup ./start.sh &'
  - name: my-app
    process: my-app
    start: 'nohup ./my-app.sh &'
```

`bash Watchdog.sh --show-config` prints the resolved settings and exits. The full schema, matching rules, and log lines are in [`Index.md`](Index.md).

---

# Safer restarts

The first restart is immediate. After each attempt Watchdog waits before trying again. The wait starts at `backoff_initial` seconds and doubles until `backoff_max`. Checks still happen on `check_interval`, so the real gap is whichever is longer.

When a service has been restarted `max_restarts` times and is still down, Watchdog logs `Giving up` and stops restarting it. If the process shows up later (you started it, or a hook did), the counters reset. With `cooldown` set above `0`, Watchdog also tries again after that quiet period.

The log says `Backing off` when it waits and `Giving up` when it stops. A crashing process cannot be restarted in a tight loop.

---

# Failure hook

`on_failure` (or `ON_FAILURE` for one process) is a shell command. Watchdog runs it after every restart attempt and once when it gives up. The command must return. A failing hook is logged; Watchdog keeps going.

This is how Watchdog runs [Steel Panda](https://github.com/pandadad0214/Steel_Panda). Steel does not have to be installed.

```yaml
on_failure: 'TASK_DIR=/path/to/recovery-tasks bash /path/to/steel-panda/steel.sh'
```

The hook sees `WATCHDOG_SERVICE_NAME`, `WATCHDOG_SERVICE_PROCESS`, `WATCHDOG_EVENT` (`restart` or `give_up`), `WATCHDOG_ATTEMPT`, `WATCHDOG_MAX_RESTARTS`, and `WATCHDOG_LOG_FILE`. A service can set its own `on_failure`, which replaces the global one. An empty `on_failure: ''` turns the hook off for that service.

---

# What it is

Watchdog Panda is one bash loop. It asks `pgrep -f` whether each configured process is running. If not, it runs that service's start command and the optional hook.

It does not phone home, open a port, or require Python or Node. The default process name `spirit-panda` is only a default pattern. Nothing in this repo talks to Spirit Panda unless you put that in a command you configure.

---

# 🛠 For developers

```
Watchdog_Panda/
├── Watchdog.sh                 # the loop
├── install.sh                  # installer used by a tagged Release
├── config/watchdog.example.yaml
├── tests/smoke.sh              # shellcheck-friendly smoke tests
├── Index.md                    # full configuration manual
├── Documents/Index.md
├── Assets/                     # logo
├── Changelog.md
└── LICENSE                     # MIT
```

```bash
shellcheck -S error -s bash Watchdog.sh install.sh tests/smoke.sh
bash tests/smoke.sh
```

Releases are automatic once a `vX.Y.Z` tag is pushed. `.github/workflows/release.yml` packages `watchdog-panda.tar.gz`, `install.sh`, and `SHA256SUMS.txt`. This changelog entry for 0.2.0 does not create that tag.

---

# 🗺️ Still planned

- Telegram or other messaging notifications
- HTTP health check endpoints
- Spirit Panda integration examples
- A status dashboard
- Optional encrypted logs

---

# 📚 Documentation

[`Index.md`](Index.md) · [`Documents/Index.md`](Documents/Index.md) · [`Changelog.md`](Changelog.md)

---

# 🪶 Panda Oath

**Build slow.  
Build steady.  
Build sovereign.**

---

# 📜 License

MIT. See [`LICENSE`](LICENSE).
