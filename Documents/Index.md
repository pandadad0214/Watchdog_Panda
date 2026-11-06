# Watchdog Panda — documentation map

Watchdog Panda 0.2.0 is a single bash loop. It checks local processes with `pgrep -f`, restarts the ones that are gone, and can run a shell hook you configure. The behavior, config schema, and log lines are specified in [`../Index.md`](../Index.md). This page is the short map.

## What runs

| Piece | Role |
|---|---|
| `Watchdog.sh` | The loop. `#!/usr/bin/env bash`. Linux, macOS, Termux |
| Environment variables | One process when no config file is loaded. Same defaults as 0.1.0 for `TARGET_PROCESS`, `START_COMMAND`, `CHECK_INTERVAL`, and `LOG_FILE` |
| `config/watchdog.yaml`, `watchdog.yaml`, or `$WATCHDOG_CONFIG` | Several services in one Watchdog process |
| `config/watchdog.example.yaml` | Commented example. Not loaded unless you point at it |
| `on_failure` / `ON_FAILURE` | Optional shell command after a restart attempt and once on give-up |
| `watchdog.log` | Append-only record of checks, backoff, give-up, and command output |

There is no package to install with pip or npm, and no separate service manager.

## Check, restart, stop

1. On each interval, `pgrep -f` decides whether the pattern is running. Watchdog ignores its own pid.
2. A missing process is restarted immediately the first time.
3. Later attempts wait. The wait starts at `backoff_initial` and doubles up to `backoff_max`. The log says `Backing off`.
4. After `max_restarts` attempts the log says `Giving up`. The start command is not run again until the process is seen running, or until `cooldown` elapses when that is set above 0.
5. Seeing the process running clears the counters.

`start` has to return. Long-running programs belong in the background (`nohup ... &`).

## Hook

`on_failure` is how Watchdog can call [Steel Panda](https://github.com/pandadad0214/Steel_Panda):

```yaml
on_failure: 'TASK_DIR=/path/to/recovery-tasks bash /path/to/steel-panda/steel.sh'
```

Steel is a separate repository. Watchdog does not ship it and does not fail if that path is absent until you actually configure the command. The hook receives `WATCHDOG_EVENT` (`restart` or `give_up`) and the service name, pattern, attempt, cap, and log path. Details are in [`../Index.md`](../Index.md).

A global hook applies to every service. A service key replaces it. An empty service hook disables it for that service.

## What is not in this tree

Telegram or other chat notifications, HTTP health endpoints, a dashboard, encrypted logs, and any Spirit Panda client. Those stay on the roadmap in [`../Changelog.md`](../Changelog.md) and [`../Index.md`](../Index.md). Spirit Panda is not notified unless a command you wrote does that.

## Develop

```bash
shellcheck -S error -s bash Watchdog.sh install.sh tests/smoke.sh
bash tests/smoke.sh
```

A GitHub Release is published when a `vX.Y.Z` tag is pushed. Version 0.2.0 in the changelog is the tree this manual describes.
