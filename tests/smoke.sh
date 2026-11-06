#!/usr/bin/env bash
# Bounded smoke tests for Watchdog Panda. Uses GNU timeout so a loop cannot hang CI.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WATCHDOG="$ROOT/Watchdog.sh"

if ! command -v timeout >/dev/null 2>&1; then
  printf 'smoke: GNU timeout is required\n' >&2
  exit 1
fi

unset WATCHDOG_CONFIG TARGET_PROCESS START_COMMAND CHECK_INTERVAL LOG_FILE \
  MAX_RESTARTS BACKOFF_INITIAL BACKOFF_MAX COOLDOWN ON_FAILURE \
  WATCHDOG_SERVICE_NAME WATCHDOG_SERVICE_PROCESS WATCHDOG_EVENT \
  WATCHDOG_ATTEMPT WATCHDOG_MAX_RESTARTS WATCHDOG_LOG_FILE || true

TMP=$(mktemp -d)
LAST_LOG=""
cleanup() {
  local ec=$?
  if [ "$ec" -ne 0 ]; then
    printf 'smoke: failed\n' >&2
    if [ -n "$LAST_LOG" ] && [ -f "$LAST_LOG" ]; then
      printf '---- %s ----\n' "$LAST_LOG" >&2
      cat "$LAST_LOG" >&2 || true
    fi
  fi
  kill_pattern "wd-smoke-live-$$" || true
  kill_pattern "wd-smoke-recover-$$" || true
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'smoke: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [ "$got" != "$want" ]; then
    fail "$label: got [$got] want [$want]"
  fi
}

count_lines() {
  if [ ! -f "$1" ]; then
    printf '0'
    return
  fi
  wc -l < "$1" | tr -d ' '
}

show_config() {
  local out err
  err=$(mktemp)
  out=$(mktemp)
  if ! "$@" >"$out" 2>"$err"; then
    cat "$err" >&2
    rm -f "$out" "$err"
    fail "show-config failed: $*"
  fi
  if [ -s "$err" ]; then
    cat "$err" >&2
    rm -f "$out" "$err"
    fail "show-config wrote to stderr: $*"
  fi
  cat "$out"
  rm -f "$out" "$err"
}

expect_fail() {
  local needle="$1"
  shift
  local err out
  err=$(mktemp)
  out=$(mktemp)
  if "$@" >"$out" 2>"$err"; then
    cat "$err" >&2
    rm -f "$err" "$out"
    fail "expected failure: $*"
  fi
  if ! grep -q "$needle" "$err"; then
    printf 'stderr:\n' >&2
    cat "$err" >&2
    rm -f "$err" "$out"
    fail "stderr missing [$needle]"
  fi
  rm -f "$err" "$out"
}

kill_pattern() {
  local pattern="$1" pids pid
  pids=$(pgrep -f "$pattern" 2>/dev/null || true)
  # shellcheck disable=SC2086
  for pid in $pids; do
    if [ "$pid" != "$$" ]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}

# --- shebang and help --------------------------------------------------------

shebang=$(head -n 1 "$WATCHDOG")
assert_eq "$shebang" "#!/usr/bin/env bash" "shebang"

help_out=$(bash "$WATCHDOG" --help)
printf '%s\n' "$help_out" | grep -q "on_failure"
printf '%s\n' "$help_out" | grep -q "Steel Panda"
expect_fail "unknown argument" timeout 3 bash "$WATCHDOG" --nope
expect_fail "too many arguments" timeout 3 bash "$WATCHDOG" --help --show-config

# --- parser ------------------------------------------------------------------

case_dir="$TMP/parse"
mkdir -p "$case_dir"

cat > "$case_dir/full.yaml" <<'EOF'
# comment
heartbeat_interval: 5s
log_file: custom.log
max_restarts: 4
backoff_initial: 2s
backoff_max: 9s
cooldown: 0s
on_failure: 'echo global'
services:
  - name: alpha
    type: process
    start: "echo hello # not-a-comment"
    max_restarts: 2
  - name: beta
    start_command: echo beta
    on_failure: 'echo local'
  - name: gamma
    process: gamma-bin
    start: echo gamma # trailing comment
    on_failure: ''
EOF

show=$(show_config env WATCHDOG_CONFIG="$case_dir/full.yaml" bash "$WATCHDOG" --show-config)
printf '%s\n' "$show" | grep -q '^mode: config$'
printf '%s\n' "$show" | grep -q '^log_file: custom.log$'
printf '%s\n' "$show" | grep -q '^services: 3$'
printf '%s\n' "$show" | grep -q '^service 0 name: alpha$'
printf '%s\n' "$show" | grep -q '^service 0 process: alpha$'
printf '%s\n' "$show" | grep -q '^service 0 start: echo hello # not-a-comment$'
printf '%s\n' "$show" | grep -q '^service 0 check_interval: 5$'
printf '%s\n' "$show" | grep -q '^service 0 max_restarts: 2$'
printf '%s\n' "$show" | grep -q '^service 0 backoff_initial: 2$'
printf '%s\n' "$show" | grep -q '^service 0 backoff_max: 9$'
printf '%s\n' "$show" | grep -q '^service 0 on_failure: echo global$'
printf '%s\n' "$show" | grep -q '^service 1 start: echo beta$'
printf '%s\n' "$show" | grep -q '^service 1 on_failure: echo local$'
printf '%s\n' "$show" | grep -q '^service 2 process: gamma-bin$'
printf '%s\n' "$show" | grep -q '^service 2 start: echo gamma$'
printf '%s\n' "$show" | grep -q '^service 2 on_failure: $'

# Globals after the list still apply. config/watchdog.yaml beats ./watchdog.yaml.
mkdir -p "$case_dir/config"
cat > "$case_dir/watchdog.yaml" <<'EOF'
check_interval: 9
services:
  - name: from-root
    start: echo root
EOF
cat > "$case_dir/config/watchdog.yaml" <<'EOF'
services:
  - name: from-dir
    start: echo dir
check_interval: 4
EOF
show=$(show_config bash -c "cd '$case_dir' && bash '$WATCHDOG' --show-config")
printf '%s\n' "$show" | grep -q '^service 0 name: from-dir$'
printf '%s\n' "$show" | grep -q '^service 0 check_interval: 4$'

# WATCHDOG_CONFIG beats auto-discovery.
show=$(show_config bash -c "cd '$case_dir' && WATCHDOG_CONFIG='$case_dir/watchdog.yaml' bash '$WATCHDOG' --show-config")
printf '%s\n' "$show" | grep -q '^service 0 name: from-root$'

# The example file is not auto-loaded from the repo root.
show=$(show_config bash -c "cd '$ROOT' && bash '$WATCHDOG' --show-config")
printf '%s\n' "$show" | grep -q '^mode: env$'
printf '%s\n' "$show" | grep -q '^service 0 name: spirit-panda$'
printf '%s\n' "$show" | grep -q '^service 0 start: ./start.sh$'
printf '%s\n' "$show" | grep -q '^service 0 max_restarts: 5$'
printf '%s\n' "$show" | grep -q '^service 0 backoff_initial: 2$'
if [ -f "$ROOT/watchdog.log" ]; then
  fail "show-config created a log in the repo"
fi

show=$(show_config env WATCHDOG_CONFIG="$ROOT/config/watchdog.example.yaml" bash "$WATCHDOG" --show-config)
printf '%s\n' "$show" | grep -q '^service 0 name: spirit-panda$'
printf '%s\n' "$show" | grep -q '^service 1 name: my-app$'
grep -q "steel-panda/steel.sh" "$ROOT/config/watchdog.example.yaml"
grep -q "Steel_Panda" "$ROOT/config/watchdog.example.yaml"

# Env overrides and a clean show-config do not create the default log.
env_case="$TMP/env-show"
mkdir -p "$env_case"
show=$(show_config bash -c "cd '$env_case' && TARGET_PROCESS=demo START_COMMAND='echo hi' CHECK_INTERVAL=3 MAX_RESTARTS=2 BACKOFF_INITIAL=1 BACKOFF_MAX=8 COOLDOWN=4 ON_FAILURE='echo hook' bash '$WATCHDOG' --show-config")
printf '%s\n' "$show" | grep -q '^mode: env$'
printf '%s\n' "$show" | grep -q '^service 0 name: demo$'
printf '%s\n' "$show" | grep -q '^service 0 start: echo hi$'
printf '%s\n' "$show" | grep -q '^service 0 check_interval: 3$'
printf '%s\n' "$show" | grep -q '^service 0 max_restarts: 2$'
printf '%s\n' "$show" | grep -q '^service 0 cooldown: 4$'
printf '%s\n' "$show" | grep -q '^service 0 on_failure: echo hook$'
if [ -e "$env_case/watchdog.log" ]; then
  fail "show-config created a log file"
fi

printf 'check_interval: 3\r\nservices:\r\n  - name: crlf\r\n    start: echo crlf\r\n' > "$case_dir/crlf.yaml"
show=$(show_config env WATCHDOG_CONFIG="$case_dir/crlf.yaml" bash "$WATCHDOG" --show-config)
printf '%s\n' "$show" | grep -q '^service 0 check_interval: 3$'

expect_fail "not found" timeout 3 env WATCHDOG_CONFIG="$case_dir/missing.yaml" bash "$WATCHDOG"
printf 'check_interval:\t5\nservices:\n  - name: a\n    start: echo a\n' > "$case_dir/tabs.yaml"
expect_fail "tabs are not allowed" timeout 3 env WATCHDOG_CONFIG="$case_dir/tabs.yaml" bash "$WATCHDOG"

printf 'alerts:\n  on_failure: true\nservices:\n  - name: a\n    start: echo a\n' > "$case_dir/alerts.yaml"
expect_fail "on_failure" timeout 3 env WATCHDOG_CONFIG="$case_dir/alerts.yaml" bash "$WATCHDOG"

printf 'on_failure: true\nservices:\n  - name: a\n    start: echo a\n' > "$case_dir/bool.yaml"
expect_fail "shell command" timeout 3 env WATCHDOG_CONFIG="$case_dir/bool.yaml" bash "$WATCHDOG"

printf 'services:\n  - name: a\n    type: socket\n    start: echo a\n' > "$case_dir/type.yaml"
expect_fail "only type" timeout 3 env WATCHDOG_CONFIG="$case_dir/type.yaml" bash "$WATCHDOG"

printf 'services:\n  - name: a\n' > "$case_dir/nostart.yaml"
expect_fail "missing start" timeout 3 env WATCHDOG_CONFIG="$case_dir/nostart.yaml" bash "$WATCHDOG"

printf 'services:\n  - name: a\n    start: echo a\n  - name: a\n    start: echo b\n' > "$case_dir/dup.yaml"
expect_fail "duplicate service name" timeout 3 env WATCHDOG_CONFIG="$case_dir/dup.yaml" bash "$WATCHDOG"

printf 'backoff_initial: 10\nbackoff_max: 2\nservices:\n  - name: a\n    start: echo a\n' > "$case_dir/back.yaml"
expect_fail "backoff_max" timeout 3 env WATCHDOG_CONFIG="$case_dir/back.yaml" bash "$WATCHDOG"

printf 'services:\n' > "$case_dir/empty.yaml"
expect_fail "at least one service" timeout 3 env WATCHDOG_CONFIG="$case_dir/empty.yaml" bash "$WATCHDOG"

expect_fail "CHECK_INTERVAL" timeout 3 bash -c "cd '$env_case' && CHECK_INTERVAL=fast bash '$WATCHDOG'"
expect_fail "ON_FAILURE" timeout 3 bash -c "cd '$env_case' && ON_FAILURE=true bash '$WATCHDOG'"

echo "ok parser"

# --- env mode: one restart, backoff, hook ------------------------------------

env_run="$TMP/env-run"
mkdir -p "$env_run"
(
  cd "$env_run"
  TARGET_PROCESS=definitely-not-running \
    START_COMMAND="echo restarted" \
    CHECK_INTERVAL=1 \
    MAX_RESTARTS=5 \
    BACKOFF_INITIAL=30 \
    BACKOFF_MAX=30 \
    ON_FAILURE='echo "$WATCHDOG_EVENT" >> env-hooks.txt' \
    LOG_FILE=watchdog.log \
    timeout 3 bash "$WATCHDOG" || true
)
LAST_LOG="$env_run/watchdog.log"
grep -q "Restart command executed" "$env_run/watchdog.log"
grep -q "Process 'definitely-not-running' not found. Restarting (attempt 1/5)..." "$env_run/watchdog.log"
grep -q "Backing off for 30 seconds" "$env_run/watchdog.log"
grep -q "Running on_failure hook" "$env_run/watchdog.log"
assert_eq "$(count_lines "$env_run/env-hooks.txt")" "1" "env hook count"
assert_eq "$(grep -c '^restarted$' "$env_run/watchdog.log" || true)" "1" "env restarts in 3s"
if grep -q "Giving up" "$env_run/watchdog.log"; then
  fail "env mode gave up during the backoff window"
fi
echo "ok env-mode"

# --- config mode: two services, hook override, no tight loop -----------------

cfg="$TMP/cfg"
mkdir -p "$cfg"
cat > "$cfg/watchdog.yaml" <<'EOF'
check_interval: 1
log_file: cfg.log
max_restarts: 4
backoff_initial: 30
backoff_max: 30
on_failure: 'echo GLOBAL >> hook-g.txt'
services:
  - name: alpha
    process: wd-smoke-missing-alpha
    start: 'echo ALPHA >> starts.txt'
    on_failure: 'echo LOCAL >> hook-a.txt'
  - name: beta
    process: wd-smoke-missing-beta
    start: 'echo BETA >> starts.txt'
    on_failure: ''
EOF
(
  cd "$cfg"
  WATCHDOG_CONFIG="$cfg/watchdog.yaml" timeout 3 bash "$WATCHDOG" || true
)
LAST_LOG="$cfg/cfg.log"
grep -q "Mode: config" "$cfg/cfg.log"
grep -q "Process 'alpha' not found" "$cfg/cfg.log"
grep -q "Process 'beta' not found" "$cfg/cfg.log"
grep -q "Restart command executed" "$cfg/cfg.log"
grep -q "Running on_failure hook for 'alpha'" "$cfg/cfg.log"
if grep -q "Running on_failure hook for 'beta'" "$cfg/cfg.log"; then
  fail "empty on_failure still ran for beta"
fi
assert_eq "$(grep -c '^ALPHA$' "$cfg/starts.txt" || true)" "1" "alpha starts"
assert_eq "$(grep -c '^BETA$' "$cfg/starts.txt" || true)" "1" "beta starts"
assert_eq "$(cat "$cfg/hook-a.txt")" "LOCAL" "local hook"
if [ -e "$cfg/hook-g.txt" ]; then
  fail "global hook ran even though the service overrode it"
fi
echo "ok config-mode"

# --- backoff, cap, give-up hook ----------------------------------------------

cap="$TMP/cap"
mkdir -p "$cap"
cat > "$cap/watchdog.yaml" <<'EOF'
check_interval: 1
log_file: cap.log
max_restarts: 2
backoff_initial: 1
backoff_max: 1
cooldown: 0
services:
  - name: crashy
    process: wd-smoke-missing-crashy
    start: 'echo start >> starts.txt'
    on_failure: 'printf "%s %s\n" "$WATCHDOG_EVENT" "$WATCHDOG_SERVICE_NAME" >> hooks.txt; exit 7'
EOF
(
  cd "$cap"
  WATCHDOG_CONFIG="$cap/watchdog.yaml" timeout 12 bash "$WATCHDOG" || true
)
LAST_LOG="$cap/cap.log"
assert_eq "$(count_lines "$cap/starts.txt")" "2" "restart cap"
grep -q "Backing off for 1 second before the next restart of 'crashy'." "$cap/cap.log"
grep -q "Giving up on 'crashy' after 2 restart attempts. No further restarts until it is seen running." "$cap/cap.log"
grep -q "on_failure hook for 'crashy' exited 7" "$cap/cap.log"
assert_eq "$(count_lines "$cap/hooks.txt")" "3" "restart hooks plus give_up"
grep -q '^restart crashy$' "$cap/hooks.txt"
grep -q '^give_up crashy$' "$cap/hooks.txt"
echo "ok backoff-cap"

# --- cooldown opens another attempt after give-up ----------------------------

cool="$TMP/cool"
mkdir -p "$cool"
cat > "$cool/watchdog.yaml" <<'EOF'
check_interval: 1
log_file: cool.log
max_restarts: 1
backoff_initial: 1
backoff_max: 1
cooldown: 2
services:
  - name: flaky
    process: wd-smoke-missing-flaky
    start: 'echo start >> starts.txt'
EOF
(
  cd "$cool"
  WATCHDOG_CONFIG="$cool/watchdog.yaml" timeout 12 bash "$WATCHDOG" || true
)
LAST_LOG="$cool/cool.log"
starts=$(count_lines "$cool/starts.txt")
if [ "$starts" -lt 2 ] || [ "$starts" -gt 5 ]; then
  fail "cooldown restarts out of range: $starts"
fi
grep -q "Giving up on 'flaky'" "$cool/cool.log"
grep -q "Cooldown elapsed for 'flaky'. Restart attempts reset." "$cool/cool.log"
echo "ok cooldown"

# --- a live process is left alone --------------------------------------------

live="$TMP/live"
mkdir -p "$live"
marker="wd-smoke-live-$$"
bash -c "exec -a $marker sleep 40" &
live_pid=$!
sleep 0.3
cat > "$live/watchdog.yaml" <<EOF
check_interval: 1
log_file: live.log
max_restarts: 3
backoff_initial: 1
backoff_max: 1
services:
  - name: alive
    process: $marker
    start: 'echo SHOULD-NOT >> starts.txt'
    on_failure: 'echo HOOKED >> hooks.txt'
EOF
(
  cd "$live"
  WATCHDOG_CONFIG="$live/watchdog.yaml" timeout 3 bash "$WATCHDOG" || true
)
LAST_LOG="$live/live.log"
kill "$live_pid" 2>/dev/null || true
if [ -e "$live/starts.txt" ] || [ -e "$live/hooks.txt" ]; then
  fail "watchdog restarted a running process"
fi
if grep -q "Restarting" "$live/live.log"; then
  fail "log shows a restart of a running process"
fi
grep -q "Watching 'alive'" "$live/live.log"
echo "ok live-process"

# --- a successful restart clears the counters --------------------------------

rec="$TMP/recover"
mkdir -p "$rec"
marker="wd-smoke-recover-$$"
cat > "$rec/watchdog.yaml" <<EOF
check_interval: 1
log_file: rec.log
max_restarts: 4
backoff_initial: 30
backoff_max: 30
services:
  - name: sleeper
    process: $marker
    start: 'echo started >> starts.txt; nohup bash -c "exec -a $marker sleep 40" >/dev/null 2>&1 &'
EOF
(
  cd "$rec"
  WATCHDOG_CONFIG="$rec/watchdog.yaml" timeout 5 bash "$WATCHDOG" || true
)
LAST_LOG="$rec/rec.log"
assert_eq "$(count_lines "$rec/starts.txt")" "1" "recovered service restarted once"
grep -q "Process 'sleeper' is running again. Restart counters reset." "$rec/rec.log"
if grep -q "Giving up" "$rec/rec.log"; then
  fail "recovered service was given up"
fi
kill_pattern "$marker"
echo "ok recovery"

# --- bad pgrep pattern does not restart --------------------------------------

bad="$TMP/badre"
mkdir -p "$bad"
cat > "$bad/watchdog.yaml" <<'EOF'
check_interval: 1
log_file: bad.log
services:
  - name: badpat
    process: "["
    start: 'echo BAD >> starts.txt'
EOF
(
  cd "$bad"
  WATCHDOG_CONFIG="$bad/watchdog.yaml" timeout 3 bash "$WATCHDOG" || true
)
LAST_LOG="$bad/bad.log"
grep -q "pgrep failed for 'badpat'" "$bad/bad.log"
assert_eq "$(grep -c "pgrep failed for 'badpat'" "$bad/bad.log" || true)" "1" "pgrep failure logged once"
if [ -e "$bad/starts.txt" ]; then
  fail "invalid pattern still ran the start command"
fi
echo "ok bad-pattern"

echo "ok smoke"
