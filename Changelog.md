# 📜 Watchdog Panda Changelog
All notable changes to this project will be documented in this file.

Dates use YYYY-MM-DD.

---

## [Unreleased]
- Planned: Telegram / messaging notifications
- Planned: Health check endpoints
- Planned: Spirit Panda integration examples

---

## [0.2.0] — 2026-11-06
- One Watchdog process can watch several services from a YAML config (`WATCHDOG_CONFIG`, `config/watchdog.yaml`, or `watchdog.yaml`). Env-var single-process mode is unchanged when no config file is present
- Restart attempts use exponential backoff and stop after a cap (`max_restarts` / `MAX_RESTARTS`). The log says when Watchdog is backing off or giving up. Optional `cooldown` retries after that quiet period
- `Watchdog.sh` uses `#!/usr/bin/env bash` so the same script runs on Linux, macOS, and Termux
- Optional `on_failure` hook, global or per service, including an example that runs a [Steel Panda](https://github.com/pandadad0214/Steel_Panda) task. Steel does not have to be installed
- Docs describe this behavior. Notifications, health endpoints, and Spirit Panda integration stay on the roadmap
- CI smoke tests cover config mode, backoff, and the hook

---

## [0.1.0] — 2026-11-04
- First GitHub Release with a one-command installer (`install.sh`); Releases now publish automatically on version tags
- `Watchdog.sh` settings can be set with environment variables (`TARGET_PROCESS`, `START_COMMAND`, `CHECK_INTERVAL`, `LOG_FILE`)
- README leads with Install / Use

---

## [2026-02-21] — Federation Documentation Pass
### Added
- Initial README describing role and architecture
- CHANGELOG.md
- docs/index.md scaffold
- Repository structure aligned with Spirit Panda

---

## [2025-XX-XX] — Initial Watchdog Loop
### Added
- Core watchdog script
- Basic process monitoring
- Auto‑restart behavior
