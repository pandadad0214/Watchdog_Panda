#!/usr/bin/env bash
# Watchdog Panda 0.2.0 — local process watchdog.
# Linux, macOS, and Termux. Bash 3.2 or newer. No other runtime.
#
# Env mode (no config file): one process from the environment.
#   TARGET_PROCESS START_COMMAND CHECK_INTERVAL LOG_FILE
#   MAX_RESTARTS BACKOFF_INITIAL BACKOFF_MAX COOLDOWN ON_FAILURE
#
# Config mode: WATCHDOG_CONFIG, else ./config/watchdog.yaml, else ./watchdog.yaml.
# Several services, same restart rules. See config/watchdog.example.yaml.
#
# start and on_failure are shell command strings. They must return.
# Background a long-running service (nohup ... &). Steel Panda is not required;
# point on_failure at it if you want a recovery task run.

VERSION="0.2.0"

set -o pipefail

die() {
  printf 'watchdog: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Watchdog Panda ${VERSION} — restart local processes when they disappear.

Usage:
  bash Watchdog.sh
  bash Watchdog.sh --help
  bash Watchdog.sh --show-config

One process (no config file), from the environment:

  TARGET_PROCESS    pgrep -f pattern (default: spirit-panda)
  START_COMMAND     shell command that restarts it (default: ./start.sh)
  CHECK_INTERVAL    seconds between checks (default: 5)
  LOG_FILE          log path (default: watchdog.log)
  MAX_RESTARTS      stop restarting after this many attempts (default: 5)
  BACKOFF_INITIAL   seconds to wait after the first restart (default: 2)
  BACKOFF_MAX       cap on that wait; it doubles each attempt (default: 60)
  COOLDOWN          after giving up, try again after this many seconds
                    (default: 0 = stay quiet until the process is seen running)
  ON_FAILURE        extra shell command after each restart attempt, and once
                    when giving up. Empty means no hook.

Several processes: copy config/watchdog.example.yaml and run
  WATCHDOG_CONFIG=/path/to/watchdog.yaml bash Watchdog.sh
A file at ./config/watchdog.yaml or ./watchdog.yaml is picked up on its own.

The hook can call Steel Panda, which does not have to be installed:
  on_failure: 'TASK_DIR=/path/to/recovery-tasks bash /path/to/steel-panda/steel.sh'
EOF
}

ACTION="run"
if [ "$#" -gt 1 ]; then
  die "too many arguments (try --help)"
fi
if [ "$#" -eq 1 ]; then
  case "$1" in
    -h|--help|help)
      ACTION="help"
      ;;
    --show-config)
      ACTION="show"
      ;;
    *)
      die "unknown argument: $1 (try --help)"
      ;;
  esac
fi

if [ "$ACTION" = "help" ]; then
  usage
  exit 0
fi

# --- string helpers ----------------------------------------------------------

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# STRIPPED, STRIP_OK=0 on an unterminated quote.
strip_comment() {
  local s="$1"
  local i=0
  local len=${#s}
  local c quote=""
  STRIP_OK=1
  while [ "$i" -lt "$len" ]; do
    c=${s:$i:1}
    if [ -n "$quote" ]; then
      if [ "$c" = "$quote" ]; then
        quote=""
      fi
    else
      if [ "$c" = '"' ] || [ "$c" = "'" ]; then
        quote=$c
      elif [ "$c" = '#' ]; then
        s=${s:0:$i}
        break
      fi
    fi
    i=$((i + 1))
  done
  if [ -n "$quote" ]; then
    STRIP_OK=0
  fi
  STRIPPED=$s
}

leading_spaces() {
  local s="$1"
  local i=0
  while [ "${s:$i:1}" = " " ]; do
    i=$((i + 1))
  done
  printf '%s' "$i"
}

# UNQUOTED, UNQUOTE_OK=0 when quotes are mismatched.
unquote_value() {
  local s="$1"
  local len q inner
  len=${#s}
  UNQUOTED=$s
  UNQUOTE_OK=1
  if [ "$len" -lt 1 ]; then
    return
  fi
  q=${s:0:1}
  if [ "$q" != '"' ] && [ "$q" != "'" ]; then
    return
  fi
  if [ "$len" -lt 2 ] || [ "${s:$((len - 1)):1}" != "$q" ]; then
    UNQUOTE_OK=0
    return
  fi
  inner=${s:1:$((len - 2))}
  case "$inner" in
    *"$q"*)
      UNQUOTE_OK=0
      return
      ;;
  esac
  UNQUOTED=$inner
}

# CANON is the base-10 integer. Returns 1 if not a whole number.
# A single trailing s is accepted (5s) for time fields when STRIP_S=1.
canon_uint() {
  local v="$1"
  if [ "${STRIP_S:-0}" -eq 1 ]; then
    case "$v" in
      *s) v=${v%s} ;;
    esac
  fi
  case "$v" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  CANON=$((10#$v))
}

is_bool_word() {
  case "$1" in
    true|false|yes|no|on|off) return 0 ;;
    *) return 1 ;;
  esac
}

# --- config ------------------------------------------------------------------

CFG_CHECK_INTERVAL=5
CFG_LOG_FILE="watchdog.log"
CFG_MAX_RESTARTS=5
CFG_BACKOFF_INITIAL=2
CFG_BACKOFF_MAX=60
CFG_COOLDOWN=0
CFG_ON_FAILURE=""

SVC_COUNT=0
SEEN_SERVICES=0
MODE=""
CONFIG_PATH=""

config_die() {
  die "$1:$2: $3"
}

mark_field() {
  local i="$1" field="$2" file="$3" n="$4"
  case "${SVC_FIELDS[$i]}" in
    *",$field,"*)
      config_die "$file" "$n" "duplicate field '$field'"
      ;;
  esac
  SVC_FIELDS[$i]="${SVC_FIELDS[$i]},$field,"
}

set_time_global() {
  local file="$1" n="$2" key="$3" value="$4" dest="$5"
  case "$dest" in
    interval|initial|bmax|cool) STRIP_S=1 ;;
    *) STRIP_S=0 ;;
  esac
  if ! canon_uint "$value"; then
    config_die "$file" "$n" "$key must be a whole number (got '$value')"
  fi
  STRIP_S=0
  case "$dest" in
    interval)
      if [ "$CANON" -lt 1 ]; then
        config_die "$file" "$n" "check_interval must be at least 1"
      fi
      CFG_CHECK_INTERVAL=$CANON
      ;;
    max)
      if [ "$CANON" -lt 1 ]; then
        config_die "$file" "$n" "max_restarts must be at least 1"
      fi
      CFG_MAX_RESTARTS=$CANON
      ;;
    initial)
      CFG_BACKOFF_INITIAL=$CANON
      ;;
    bmax)
      CFG_BACKOFF_MAX=$CANON
      ;;
    cool)
      CFG_COOLDOWN=$CANON
      ;;
  esac
}

note_global() {
  local key="$1" file="$2" n="$3"
  case "${GOT_GLOBALS:-}" in
    *"|$key|"*) config_die "$file" "$n" "duplicate setting '$key'" ;;
  esac
  GOT_GLOBALS="${GOT_GLOBALS:-}|$key|"
}

set_global() {
  local key="$1" value="$2" file="$3" n="$4"
  case "$key" in
    check_interval|heartbeat_interval)
      note_global "check_interval" "$file" "$n"
      set_time_global "$file" "$n" "check_interval" "$value" "interval"
      ;;
    log_file)
      note_global "log_file" "$file" "$n"
      if [ -z "$value" ]; then
        config_die "$file" "$n" "log_file must not be empty"
      fi
      case "$value" in
        -*) config_die "$file" "$n" "log_file must not start with '-'" ;;
      esac
      CFG_LOG_FILE=$value
      ;;
    max_restarts)
      note_global "max_restarts" "$file" "$n"
      set_time_global "$file" "$n" "max_restarts" "$value" "max"
      ;;
    backoff_initial)
      note_global "backoff_initial" "$file" "$n"
      set_time_global "$file" "$n" "backoff_initial" "$value" "initial"
      ;;
    backoff_max)
      note_global "backoff_max" "$file" "$n"
      set_time_global "$file" "$n" "backoff_max" "$value" "bmax"
      ;;
    cooldown)
      note_global "cooldown" "$file" "$n"
      set_time_global "$file" "$n" "cooldown" "$value" "cool"
      ;;
    on_failure)
      note_global "on_failure" "$file" "$n"
      if is_bool_word "$value"; then
        config_die "$file" "$n" "on_failure must be a shell command, not '$value'. Example: on_failure: 'echo failed'"
      fi
      CFG_ON_FAILURE=$value
      ;;
    services)
      note_global "services" "$file" "$n"
      if [ -n "$value" ]; then
        config_die "$file" "$n" "services must be a list of '- name:' entries"
      fi
      if [ "$SEEN_SERVICES" -eq 1 ]; then
        config_die "$file" "$n" "duplicate services list"
      fi
      SEEN_SERVICES=1
      ;;
    alerts|notify_spirit|trigger_steel)
      config_die "$file" "$n" "'$key' is not a Watchdog setting. Use on_failure with a shell command"
      ;;
    *)
      config_die "$file" "$n" "unknown setting '$key'"
      ;;
  esac
}

begin_service() {
  local i="$SVC_COUNT"
  SVC_NAME[$i]=""
  SVC_PROCESS[$i]=""
  SVC_START[$i]=""
  SVC_INTERVAL[$i]=""
  SVC_MAX[$i]=""
  SVC_BACKOFF_INITIAL[$i]=""
  SVC_BACKOFF_MAX[$i]=""
  SVC_COOLDOWN[$i]=""
  SVC_HOOK[$i]=""
  SVC_HOOK_SET[$i]=0
  SVC_FIELDS[$i]=""
  SVC_COUNT=$((i + 1))
}

set_service_time() {
  local file="$1" n="$2" i="$3" key="$4" value="$5" dest="$6"
  case "$dest" in
    interval|initial|bmax|cool) STRIP_S=1 ;;
    *) STRIP_S=0 ;;
  esac
  if ! canon_uint "$value"; then
    config_die "$file" "$n" "$key must be a whole number (got '$value')"
  fi
  STRIP_S=0
  case "$dest" in
    interval)
      if [ "$CANON" -lt 1 ]; then
        config_die "$file" "$n" "check_interval must be at least 1"
      fi
      SVC_INTERVAL[$i]=$CANON
      ;;
    max)
      if [ "$CANON" -lt 1 ]; then
        config_die "$file" "$n" "max_restarts must be at least 1"
      fi
      SVC_MAX[$i]=$CANON
      ;;
    initial) SVC_BACKOFF_INITIAL[$i]=$CANON ;;
    bmax) SVC_BACKOFF_MAX[$i]=$CANON ;;
    cool) SVC_COOLDOWN[$i]=$CANON ;;
  esac
}

set_service_field() {
  local i="$1" key="$2" value="$3" file="$4" n="$5"
  case "$key" in
    heartbeat_interval) key="check_interval" ;;
    start_command) key="start" ;;
  esac
  mark_field "$i" "$key" "$file" "$n"
  case "$key" in
    name)
      if [ -z "$value" ]; then
        config_die "$file" "$n" "name must not be empty"
      fi
      SVC_NAME[$i]=$value
      ;;
    process)
      SVC_PROCESS[$i]=$value
      ;;
    start|start_command)
      if [ -z "$value" ]; then
        config_die "$file" "$n" "start must not be empty"
      fi
      SVC_START[$i]=$value
      ;;
    type)
      if [ "$value" != "process" ]; then
        config_die "$file" "$n" "only type 'process' is supported (got '$value')"
      fi
      ;;
    check_interval|heartbeat_interval)
      set_service_time "$file" "$n" "$i" "check_interval" "$value" "interval"
      ;;
    max_restarts)
      set_service_time "$file" "$n" "$i" "max_restarts" "$value" "max"
      ;;
    backoff_initial)
      set_service_time "$file" "$n" "$i" "backoff_initial" "$value" "initial"
      ;;
    backoff_max)
      set_service_time "$file" "$n" "$i" "backoff_max" "$value" "bmax"
      ;;
    cooldown)
      set_service_time "$file" "$n" "$i" "cooldown" "$value" "cool"
      ;;
    on_failure)
      if is_bool_word "$value"; then
        config_die "$file" "$n" "on_failure must be a shell command, not '$value'"
      fi
      SVC_HOOK[$i]=$value
      SVC_HOOK_SET[$i]=1
      ;;
    *)
      config_die "$file" "$n" "unknown service field '$key'"
      ;;
  esac
}

# KEY, VALUE. Returns 1 if the line is not key: value.
parse_kv() {
  local content="$1" key value
  case "$content" in
    *:*)
      key=${content%%:*}
      value=${content#*:}
      ;;
    *)
      return 1
      ;;
  esac
  key=$(trim "$key")
  value=$(trim "$value")
  case "$key" in
    ""|*[!A-Za-z0-9_]*)
      return 1
      ;;
  esac
  case "$key" in
    [A-Za-z]*)
      ;;
    *)
      return 1
      ;;
  esac
  unquote_value "$value"
  if [ "$UNQUOTE_OK" -ne 1 ]; then
    return 2
  fi
  KEY=$key
  VALUE=$UNQUOTED
  return 0
}

parse_config_file() {
  local file="$1"
  local line n=0 indent content item idx kv_rc j
  if [ ! -f "$file" ]; then
    die "config file not found: $file"
  fi
  if [ ! -r "$file" ]; then
    die "cannot read config file: $file"
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%$'\r'}
    case "$line" in
      *$'\t'*) config_die "$file" "$n" "tabs are not allowed; use spaces" ;;
    esac
    strip_comment "$line"
    if [ "$STRIP_OK" -ne 1 ]; then
      config_die "$file" "$n" "unterminated quote"
    fi
    line=$STRIPPED
    content=$(trim "$line")
    if [ -z "$content" ]; then
      continue
    fi
    indent=$(leading_spaces "$line")
    if [ "$indent" -eq 0 ]; then
      parse_kv "$content"
      kv_rc=$?
      if [ "$kv_rc" -eq 2 ]; then
        config_die "$file" "$n" "mismatched quotes"
      fi
      if [ "$kv_rc" -ne 0 ]; then
        config_die "$file" "$n" "expected 'key: value'"
      fi
      set_global "$KEY" "$VALUE" "$file" "$n"
      continue
    fi
    if [ "$SEEN_SERVICES" -ne 1 ]; then
      config_die "$file" "$n" "indented line before services:"
    fi
    case "$content" in
      "- "*)
        item=$(trim "${content#- }")
        begin_service
        idx=$((SVC_COUNT - 1))
        parse_kv "$item"
        kv_rc=$?
        if [ "$kv_rc" -eq 2 ]; then
          config_die "$file" "$n" "mismatched quotes"
        fi
        if [ "$kv_rc" -ne 0 ]; then
          config_die "$file" "$n" "expected '- key: value'"
        fi
        set_service_field "$idx" "$KEY" "$VALUE" "$file" "$n"
        ;;
      "-"*)
        config_die "$file" "$n" "expected '- key: value'"
        ;;
      *)
        if [ "$SVC_COUNT" -eq 0 ]; then
          config_die "$file" "$n" "service field before '- name:'"
        fi
        idx=$((SVC_COUNT - 1))
        parse_kv "$content"
        kv_rc=$?
        if [ "$kv_rc" -eq 2 ]; then
          config_die "$file" "$n" "mismatched quotes"
        fi
        if [ "$kv_rc" -ne 0 ]; then
          config_die "$file" "$n" "expected 'key: value'"
        fi
        set_service_field "$idx" "$KEY" "$VALUE" "$file" "$n"
        ;;
    esac
  done < "$file"

  if [ "$SEEN_SERVICES" -ne 1 ] || [ "$SVC_COUNT" -eq 0 ]; then
    die "$file: services: must list at least one service"
  fi
  if [ "$CFG_BACKOFF_MAX" -lt "$CFG_BACKOFF_INITIAL" ]; then
    die "$file: backoff_max ($CFG_BACKOFF_MAX) is less than backoff_initial ($CFG_BACKOFF_INITIAL)"
  fi

  idx=0
  while [ "$idx" -lt "$SVC_COUNT" ]; do
    if [ -z "${SVC_NAME[$idx]}" ]; then
      die "$file: service $((idx + 1)) is missing name"
    fi
    if [ -z "${SVC_START[$idx]}" ]; then
      die "$file: service '${SVC_NAME[$idx]}' is missing start"
    fi
    if [ -z "${SVC_PROCESS[$idx]}" ]; then
      SVC_PROCESS[$idx]=${SVC_NAME[$idx]}
    fi
    case "${SVC_PROCESS[$idx]}" in
      -*)
        die "$file: service '${SVC_NAME[$idx]}' process pattern must not start with '-'"
        ;;
      "")
        die "$file: service '${SVC_NAME[$idx]}' process pattern must not be empty"
        ;;
    esac
    if [ -z "${SVC_INTERVAL[$idx]}" ]; then
      SVC_INTERVAL[$idx]=$CFG_CHECK_INTERVAL
    fi
    if [ -z "${SVC_MAX[$idx]}" ]; then
      SVC_MAX[$idx]=$CFG_MAX_RESTARTS
    fi
    if [ -z "${SVC_BACKOFF_INITIAL[$idx]}" ]; then
      SVC_BACKOFF_INITIAL[$idx]=$CFG_BACKOFF_INITIAL
    fi
    if [ -z "${SVC_BACKOFF_MAX[$idx]}" ]; then
      SVC_BACKOFF_MAX[$idx]=$CFG_BACKOFF_MAX
    fi
    if [ -z "${SVC_COOLDOWN[$idx]}" ]; then
      SVC_COOLDOWN[$idx]=$CFG_COOLDOWN
    fi
    if [ "${SVC_HOOK_SET[$idx]}" -eq 0 ]; then
      SVC_HOOK[$idx]=$CFG_ON_FAILURE
    fi
    if [ "${SVC_BACKOFF_MAX[$idx]}" -lt "${SVC_BACKOFF_INITIAL[$idx]}" ]; then
      die "$file: service '${SVC_NAME[$idx]}' backoff_max is less than backoff_initial"
    fi
    j=$((idx + 1))
    while [ "$j" -lt "$SVC_COUNT" ]; do
      if [ "${SVC_NAME[$idx]}" = "${SVC_NAME[$j]}" ]; then
        die "$file: duplicate service name '${SVC_NAME[$idx]}'"
      fi
      j=$((j + 1))
    done
    idx=$((idx + 1))
  done

  LOG_FILE=$CFG_LOG_FILE
  MODE="config"
  CONFIG_PATH=$file
}

validate_env_number() {
  local name="$1" value="$2" min="$3"
  STRIP_S=0
  if ! canon_uint "$value"; then
    die "$name must be a whole number (got '$value')"
  fi
  if [ "$CANON" -lt "$min" ]; then
    die "$name must be at least $min"
  fi
  ENV_NUM=$CANON
}

load_env_mode() {
  local target start interval logfile maxreb initial bmax cool hook
  target=${TARGET_PROCESS:-spirit-panda}
  start=${START_COMMAND:-./start.sh}
  interval=${CHECK_INTERVAL:-5}
  logfile=${LOG_FILE:-watchdog.log}
  maxreb=${MAX_RESTARTS:-5}
  initial=${BACKOFF_INITIAL:-2}
  bmax=${BACKOFF_MAX:-60}
  cool=${COOLDOWN:-0}
  hook=${ON_FAILURE:-}

  if [ -z "$target" ]; then
    die "TARGET_PROCESS must not be empty"
  fi
  case "$target" in
    -*) die "TARGET_PROCESS must not start with '-'" ;;
  esac
  if [ -z "$start" ]; then
    die "START_COMMAND must not be empty"
  fi
  if [ -z "$logfile" ]; then
    die "LOG_FILE must not be empty"
  fi
  case "$logfile" in
    -*) die "LOG_FILE must not start with '-'" ;;
  esac
  if is_bool_word "$hook"; then
    die "ON_FAILURE must be a shell command, not '$hook'"
  fi

  validate_env_number "CHECK_INTERVAL" "$interval" 1
  interval=$ENV_NUM
  validate_env_number "MAX_RESTARTS" "$maxreb" 1
  maxreb=$ENV_NUM
  validate_env_number "BACKOFF_INITIAL" "$initial" 0
  initial=$ENV_NUM
  validate_env_number "BACKOFF_MAX" "$bmax" 0
  bmax=$ENV_NUM
  validate_env_number "COOLDOWN" "$cool" 0
  cool=$ENV_NUM
  if [ "$bmax" -lt "$initial" ]; then
    die "BACKOFF_MAX ($bmax) is less than BACKOFF_INITIAL ($initial)"
  fi

  CFG_CHECK_INTERVAL=$interval
  CFG_LOG_FILE=$logfile
  CFG_MAX_RESTARTS=$maxreb
  CFG_BACKOFF_INITIAL=$initial
  CFG_BACKOFF_MAX=$bmax
  CFG_COOLDOWN=$cool
  CFG_ON_FAILURE=$hook

  SVC_COUNT=1
  SVC_NAME[0]=$target
  SVC_PROCESS[0]=$target
  SVC_START[0]=$start
  SVC_INTERVAL[0]=$interval
  SVC_MAX[0]=$maxreb
  SVC_BACKOFF_INITIAL[0]=$initial
  SVC_BACKOFF_MAX[0]=$bmax
  SVC_COOLDOWN[0]=$cool
  SVC_HOOK[0]=$hook
  SVC_HOOK_SET[0]=1
  LOG_FILE=$logfile
  MODE="env"
  CONFIG_PATH=""
}

resolve_and_load() {
  if [ -n "${WATCHDOG_CONFIG:-}" ]; then
    parse_config_file "$WATCHDOG_CONFIG"
    return
  fi
  if [ -f config/watchdog.yaml ]; then
    parse_config_file "config/watchdog.yaml"
    return
  fi
  if [ -f watchdog.yaml ]; then
    parse_config_file "watchdog.yaml"
    return
  fi
  load_env_mode
}

show_config() {
  local i=0 shown_config
  printf 'version: %s\n' "$VERSION"
  printf 'mode: %s\n' "$MODE"
  if [ -n "$CONFIG_PATH" ]; then
    shown_config=$CONFIG_PATH
  else
    shown_config="-"
  fi
  printf 'config: %s\n' "$shown_config"
  printf 'log_file: %s\n' "$LOG_FILE"
  printf 'services: %s\n' "$SVC_COUNT"
  while [ "$i" -lt "$SVC_COUNT" ]; do
    printf 'service %s name: %s\n' "$i" "${SVC_NAME[$i]}"
    printf 'service %s process: %s\n' "$i" "${SVC_PROCESS[$i]}"
    printf 'service %s start: %s\n' "$i" "${SVC_START[$i]}"
    printf 'service %s check_interval: %s\n' "$i" "${SVC_INTERVAL[$i]}"
    printf 'service %s max_restarts: %s\n' "$i" "${SVC_MAX[$i]}"
    printf 'service %s backoff_initial: %s\n' "$i" "${SVC_BACKOFF_INITIAL[$i]}"
    printf 'service %s backoff_max: %s\n' "$i" "${SVC_BACKOFF_MAX[$i]}"
    printf 'service %s cooldown: %s\n' "$i" "${SVC_COOLDOWN[$i]}"
    printf 'service %s on_failure: %s\n' "$i" "${SVC_HOOK[$i]}"
    i=$((i + 1))
  done
}

# --- runtime -----------------------------------------------------------------

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

# Seconds to wait after attempt N (1-based). Doubles each attempt, capped.
backoff_delay() {
  local attempt="$1" initial="$2" max="$3"
  local shift i delay
  shift=$((attempt - 1))
  if [ "$shift" -lt 0 ]; then
    shift=0
  fi
  if [ "$shift" -gt 16 ]; then
    shift=16
  fi
  delay=$initial
  if [ "$max" -lt "$delay" ]; then
    delay=$max
  fi
  i=0
  while [ "$i" -lt "$shift" ]; do
    if [ "$delay" -ge "$max" ]; then
      delay=$max
      break
    fi
    if [ "$max" -gt 0 ] && [ "$delay" -gt $((max / 2)) ]; then
      delay=$max
      break
    fi
    delay=$((delay * 2))
    i=$((i + 1))
  done
  printf '%s' "$delay"
}

# PROC_STATE=up|down|bad and PROC_RC for bad.
detect_process() {
  local pattern="$1"
  local pids pid rc
  rc=0
  pids=$(pgrep -f "$pattern" 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
    PROC_STATE="bad"
    PROC_RC=$rc
    return
  fi
  # pgrep prints one pid per line; split on purpose.
  # shellcheck disable=SC2086
  for pid in $pids; do
    if [ "$pid" != "$$" ]; then
      PROC_STATE="up"
      PROC_RC=0
      return
    fi
  done
  PROC_STATE="down"
  PROC_RC=1
}

plural_seconds() {
  if [ "$1" -eq 1 ]; then
    printf '1 second'
  else
    printf '%s seconds' "$1"
  fi
}

run_hook() {
  local i="$1" event="$2" attempt="$3"
  local cmd name rc
  cmd=${SVC_HOOK[$i]}
  if [ -z "$cmd" ]; then
    return 0
  fi
  name=${SVC_NAME[$i]}
  log "Running on_failure hook for '$name' (event=${event}, attempt=${attempt})."
  WATCHDOG_SERVICE_NAME="$name" \
    WATCHDOG_SERVICE_PROCESS="${SVC_PROCESS[$i]}" \
    WATCHDOG_EVENT="$event" \
    WATCHDOG_ATTEMPT="$attempt" \
    WATCHDOG_MAX_RESTARTS="${SVC_MAX[$i]}" \
    WATCHDOG_LOG_FILE="$LOG_FILE" \
    bash -c "$cmd" >> "$LOG_FILE" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    log "on_failure hook for '$name' finished."
  else
    log "on_failure hook for '$name' exited ${rc}. Watchdog will keep going."
  fi
}

check_service() {
  local i="$1"
  local now name delay rc next_num waited
  now=$(date '+%s')
  name=${SVC_NAME[$i]}
  detect_process "${SVC_PROCESS[$i]}"

  if [ "$PROC_STATE" = "bad" ]; then
    if [ "${ST_BAD[$i]}" -eq 0 ]; then
      log "pgrep failed for '$name' (exit ${PROC_RC}). This check was skipped."
      ST_BAD[$i]=1
    fi
    return
  fi
  ST_BAD[$i]=0

  if [ "$PROC_STATE" = "up" ]; then
    if [ "${ST_ATTEMPTS[$i]}" -gt 0 ] || [ "${ST_GAVE_UP[$i]}" -eq 1 ]; then
      log "Process '$name' is running again. Restart counters reset."
    fi
    ST_ATTEMPTS[$i]=0
    ST_GAVE_UP[$i]=0
    ST_GAVE_UP_AT[$i]=0
    ST_NEXT_ATTEMPT[$i]=0
    return
  fi

  if [ "${ST_GAVE_UP[$i]}" -eq 1 ]; then
    if [ "${SVC_COOLDOWN[$i]}" -gt 0 ]; then
      waited=$((now - ST_GAVE_UP_AT[$i]))
      if [ "$waited" -ge "${SVC_COOLDOWN[$i]}" ]; then
        log "Cooldown elapsed for '$name'. Restart attempts reset."
        ST_GAVE_UP[$i]=0
        ST_ATTEMPTS[$i]=0
        ST_NEXT_ATTEMPT[$i]=0
      else
        return
      fi
    else
      return
    fi
  fi

  if [ "${ST_NEXT_ATTEMPT[$i]}" -gt "$now" ]; then
    return
  fi

  next_num=$((ST_ATTEMPTS[$i] + 1))
  if [ "$next_num" -gt "${SVC_MAX[$i]}" ]; then
    ST_GAVE_UP[$i]=1
    ST_GAVE_UP_AT[$i]=$now
    if [ "${SVC_COOLDOWN[$i]}" -gt 0 ]; then
      log "Giving up on '$name' after ${ST_ATTEMPTS[$i]} restart attempts. No further restarts until it is seen running or the $(plural_seconds "${SVC_COOLDOWN[$i]}") cooldown elapses."
    else
      log "Giving up on '$name' after ${ST_ATTEMPTS[$i]} restart attempts. No further restarts until it is seen running."
    fi
    run_hook "$i" "give_up" "${ST_ATTEMPTS[$i]}"
    return
  fi

  log "Process '$name' not found. Restarting (attempt ${next_num}/${SVC_MAX[$i]})..."
  bash -c "${SVC_START[$i]}" >> "$LOG_FILE" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    log "Restart command for '$name' exited ${rc}."
  fi
  log "Restart command executed."
  ST_ATTEMPTS[$i]=$next_num
  run_hook "$i" "restart" "$next_num"

  delay=$(backoff_delay "$next_num" "${SVC_BACKOFF_INITIAL[$i]}" "${SVC_BACKOFF_MAX[$i]}")
  now=$(date '+%s')
  if [ "$delay" -gt 0 ]; then
    ST_NEXT_ATTEMPT[$i]=$((now + delay))
    log "Backing off for $(plural_seconds "$delay") before the next restart of '$name'."
  else
    ST_NEXT_ATTEMPT[$i]=0
  fi
}

open_log() {
  local log_dir
  case "$LOG_FILE" in
    -*) die "log file path must not start with '-'" ;;
  esac
  log_dir=$(dirname "$LOG_FILE")
  if [ ! -d "$log_dir" ]; then
    die "log directory does not exist: $log_dir"
  fi
  if ! touch "$LOG_FILE"; then
    die "cannot write log file: $LOG_FILE"
  fi
}

run_loop() {
  local i now earliest sleep_for count
  if ! command -v pgrep >/dev/null 2>&1; then
    die "pgrep is required"
  fi
  open_log
  count=$SVC_COUNT
  now=$(date '+%s')
  i=0
  while [ "$i" -lt "$count" ]; do
    ST_ATTEMPTS[$i]=0
    ST_NEXT_ATTEMPT[$i]=0
    ST_GAVE_UP[$i]=0
    ST_GAVE_UP_AT[$i]=0
    ST_NEXT_CHECK[$i]=$now
    ST_BAD[$i]=0
    i=$((i + 1))
  done

  log "Watchdog Panda ${VERSION} started."
  if [ "$MODE" = "config" ]; then
    log "Mode: config. File: ${CONFIG_PATH}."
  else
    log "Mode: env."
  fi
  i=0
  while [ "$i" -lt "$count" ]; do
    log "Watching '${SVC_NAME[$i]}' (process pattern '${SVC_PROCESS[$i]}', every ${SVC_INTERVAL[$i]}s, max ${SVC_MAX[$i]} restarts, backoff ${SVC_BACKOFF_INITIAL[$i]}-${SVC_BACKOFF_MAX[$i]}s, cooldown ${SVC_COOLDOWN[$i]}s)."
    i=$((i + 1))
  done

  while true; do
    now=$(date '+%s')
    earliest=""
    i=0
    while [ "$i" -lt "$count" ]; do
      if [ "$now" -ge "${ST_NEXT_CHECK[$i]}" ]; then
        check_service "$i"
        now=$(date '+%s')
        ST_NEXT_CHECK[$i]=$((now + SVC_INTERVAL[$i]))
      fi
      if [ -z "$earliest" ] || [ "${ST_NEXT_CHECK[$i]}" -lt "$earliest" ]; then
        earliest=${ST_NEXT_CHECK[$i]}
      fi
      i=$((i + 1))
    done
    sleep_for=$((earliest - now))
    if [ "$sleep_for" -lt 1 ]; then
      sleep_for=1
    fi
    sleep "$sleep_for"
  done
}

resolve_and_load

if [ "$ACTION" = "show" ]; then
  show_config
  exit 0
fi

run_loop
