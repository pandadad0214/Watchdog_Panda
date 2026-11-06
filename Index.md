# 🛡️ Watchdog Panda

Watchdog Panda 0.2.0 is a local process watchdog. One bash process checks `pgrep -f` on an interval, restarts anything that has disappeared, backs off when a restart does not stick, and can run a shell command you configure. Linux, macOS, and Termux. No Python or Node runtime.

The manual below matches `Watchdog.sh`. [`config/watchdog.example.yaml`](config/watchdog.example.yaml) is a commented copy of the same settings.

---

# Install / Use

From a clone (this is version 0.2.0):

```bash
git clone https://github.com/pandadad0214/Watchdog_Panda.git
cd Watchdog_Panda
TARGET_PROCESS="my-app" START_COMMAND="nohup ./my-app.sh &" bash Watchdog.sh
```

The one-command installer downloads the latest **tagged** Release into `~/watchdog-panda`:

```bash
curl -fsSL https://github.com/pandadad0214/Watchdog_Panda/releases/latest/download/install.sh | bash
```

Clone the repository to run 0.2.0 until a `v0.2.0` tag is published. After that, the installer and the `watchdog-panda.tar.gz` asset on the Release (check `SHA256SUMS.txt`) are the same tree.

Stop Watchdog with Ctrl+C.

---

# One process (environment)

If none of the config files below exist, Watchdog watches a single process. Unset variables use these defaults, which are the 0.1.0 defaults plus the restart limits:

| Variable | Default | Meaning |
|---|---|---|
| `TARGET_PROCESS` | `spirit-panda` | Extended regular expression for `pgrep -f` |
| `START_COMMAND` | `./start.sh` | Shell command run to bring it back |
| `CHECK_INTERVAL` | `5` | Seconds between checks. Minimum 1 |
| `LOG_FILE` | `watchdog.log` | Append-only event log |
| `MAX_RESTARTS` | `5` | Restart attempts before giving up. Minimum 1 |
| `BACKOFF_INITIAL` | `2` | Wait after the first restart, in seconds |
| `BACKOFF_MAX` | `60` | Cap on that wait. Must be ≥ `BACKOFF_INITIAL` |
| `COOLDOWN` | `0` | After giving up, seconds before the counters reset. `0` waits until the process is seen running |
| `ON_FAILURE` | empty | Shell command run after each restart attempt and once on give-up |

```bash
TARGET_PROCESS="my-app" \
START_COMMAND="nohup ./my-app.sh &" \
ON_FAILURE='TASK_DIR=/path/to/recovery-tasks bash /path/to/steel-panda/steel.sh' \
bash Watchdog.sh
```

`bash Watchdog.sh --show-config` prints the resolved mode and exits without opening the log. `bash Watchdog.sh --help` prints the same settings.

---

# Several services (config file)

Watchdog reads the first file that exists:

1. `$WATCHDOG_CONFIG` — if this is set, the file must exist
2. `./config/watchdog.yaml`
3. `./watchdog.yaml`

`config/watchdog.example.yaml` is never loaded on its own. Copy it, then edit.

The file is a small YAML subset parsed by `Watchdog.sh`:

- Spaces only. A tab is an error.
- `key: value` at the left margin, and one `services:` list.
- List entries are indented lines starting with `- key: value`.
- `#` starts a comment outside quotes. Quotes are `'` or `"` around the whole value. Use the other quote inside. No escape sequences and no multi-line values.
- A trailing `s` on time fields is accepted (`5s` and `5` are the same).
- Unknown keys are errors, so a typo cannot be skipped.
- `heartbeat_interval` is an alias of `check_interval`. `start_command` is an alias of `start`.
- `type` may be omitted or set to `process`. Other types are rejected.

```yaml
check_interval: 5
log_file: watchdog.log
max_restarts: 5
backoff_initial: 2
backoff_max: 60
cooldown: 0
on_failure: 'TASK_DIR=/path/to/recovery-tasks bash /path/to/steel-panda/steel.sh'

services:
  - name: spirit-panda
    type: process
    process: spirit-panda
    start: 'nohup ./start.sh &'

  - name: my-app
    process: my-app
    start: 'nohup ./my-app.sh &'
    max_restarts: 3
    backoff_initial: 5s
    backoff_max: 120
    on_failure: 'echo my-app failed >> /tmp/my-app.hook'
```

Global keys may appear before or after `services:`. A per-service value replaces the global one. Omitted per-service values inherit the global.

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | Label used in the log. Must be unique |
| `process` | no | `pgrep -f` pattern. Defaults to `name` |
| `start` | yes | Shell command that restarts this service |
| `check_interval` | no | Seconds between checks for this service |
| `max_restarts` | no | Restart cap for this service |
| `backoff_initial` | no | First backoff, in seconds |
| `backoff_max` | no | Backoff cap, in seconds |
| `cooldown` | no | Quiet period after give-up, in seconds |
| `on_failure` | no | Hook command. Empty string disables the global hook for this service |
| `type` | no | Only `process` |

`on_failure: true` is rejected. The hook is a command string, not a boolean.

There is no `alerts:` block. Notifications and Spirit Panda are not built in. Put whatever you want to run in `on_failure`.

---

# How a check works

On each check of a service:

1. `pgrep -f` looks for the pattern. Watchdog's own pid is ignored, so a pattern that appears only in Watchdog's command line does not count as "up".
2. If any other pid matches, the service is up. Restart counters reset, and the log says so when a previous attempt or give-up was in progress.
3. If it is down and the backoff window has not elapsed, Watchdog waits.
4. If the next attempt would pass `max_restarts`, Watchdog logs `Giving up`, runs the hook once with `WATCHDOG_EVENT=give_up`, and does not run `start`.
5. Otherwise it runs `start`, logs `Restart command executed`, runs the hook with `WATCHDOG_EVENT=restart`, then logs `Backing off`.

The first restart is immediate. After attempt number N the wait is `backoff_initial * 2^(N-1)` seconds, capped at `backoff_max`. The loop also sleeps until the next `check_interval`, so the gap between attempts is the longer of the backoff and the interval.

`start` and `on_failure` run in the foreground through `bash -c`. They have to return, or the loop pauses for every service. Background a daemon inside the command:

```bash
start: 'nohup ./my-app.sh >/var/tmp/my-app.log 2>&1 &'
```

A non-zero exit from `start` or the hook is written to the log. Watchdog keeps running.

While a service is given up, Watchdog still checks it. Seeing it running clears the give-up. If `cooldown` is greater than 0, the counters also clear after that many seconds and Watchdog tries again. The log says `Cooldown elapsed` when that happens.

`pgrep` exit codes other than "found" and "not found" (a bad regular expression, for example) are logged once and do not trigger a restart.

---

# Process patterns

`process` is an extended regular expression, the same kind `pgrep -f` uses, matched against the full command line. It must not start with `-`.

Choose a pattern that identifies the target and does not match Watchdog itself or unrelated processes. `bash` is a poor pattern. A unique token in the service command is a good one.

---

# Failure hook and Steel Panda

The hook is the supported way to run another program when a service dies. [Steel Panda](https://github.com/pandadad0214/Steel_Panda) is a separate local task runner: it executes the `*.sh` files in a directory. Watchdog does not import it, vendor it, or check that it is installed.

```yaml
on_failure: 'TASK_DIR=/path/to/recovery-tasks bash /path/to/steel-panda/steel.sh'
```

`TASK_DIR` is Steel's own setting for that task folder. Point it at scripts that are safe to run when the watched process is down. Steel's finish pass is expected to honor `TASK_DIR`, exit codes, and stop-on-error; Watchdog only runs the command string and records the exit code.

Environment passed to the hook:

| Variable | Value |
|---|---|
| `WATCHDOG_SERVICE_NAME` | `name` from the config, or `TARGET_PROCESS` |
| `WATCHDOG_SERVICE_PROCESS` | the `pgrep` pattern |
| `WATCHDOG_EVENT` | `restart` or `give_up` |
| `WATCHDOG_ATTEMPT` | how many restarts have been attempted |
| `WATCHDOG_MAX_RESTARTS` | the cap for this service |
| `WATCHDOG_LOG_FILE` | the log path |

A per-service `on_failure` replaces the global command. Set it to `''` to run no hook for that service while other services keep the global one.

---

# Log

Each line looks like:

```text
[2026-11-06 16:42:00] Process 'my-app' not found. Restarting (attempt 1/5)...
[2026-11-06 16:42:00] Restart command executed.
[2026-11-06 16:42:00] Running on_failure hook for 'my-app' (event=restart, attempt=1).
[2026-11-06 16:42:00] Backing off for 2 seconds before the next restart of 'my-app'.
[2026-11-06 16:42:08] Giving up on 'my-app' after 5 restart attempts. No further restarts until it is seen running.
```

Stdout and stderr from `start` and from the hook are appended to the same file. The log directory must already exist. Paths are relative to the directory you started Watchdog from.

---

# Commands

```bash
bash Watchdog.sh                 # watch until Ctrl+C
bash Watchdog.sh --show-config   # print resolved settings and exit 0
bash Watchdog.sh --help
```

Configuration mistakes exit 1 with a `watchdog:` line on stderr before the loop starts. `pgrep` has to be on `PATH` (procps on Linux and Termux, built in on macOS).

---

# Testing

From a clone, on a machine with `shellcheck`, GNU `timeout`, and `pgrep`:

```bash
shellcheck -S error -s bash Watchdog.sh install.sh tests/smoke.sh
bash tests/smoke.sh
```

The smoke test covers env mode, config mode, backoff, the restart cap, cooldown, the hook (including a hook that exits non-zero), a process that is already up, and a restart that comes back. Each run is wrapped in `timeout`.

---

# Still planned

These are not implemented:

- Telegram or other messaging notifications
- HTTP health check endpoints
- A status dashboard
- Spirit Panda integration examples
- Optional encrypted logs
- Multi-agent heartbeat mesh

---

# License

MIT. See [`LICENSE`](LICENSE).
