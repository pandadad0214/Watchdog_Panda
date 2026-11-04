#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# 🛡️ Watchdog Panda — Core Watchdog Loop
# Monitors a target process and restarts it
# ==========================================

# Each setting can be overridden with an environment variable of the same name.
TARGET_PROCESS="${TARGET_PROCESS:-spirit-panda}"   # name of the process to watch
START_COMMAND="${START_COMMAND:-./start.sh}"       # command to restart it
LOG_FILE="${LOG_FILE:-watchdog.log}"               # log file for events
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"              # seconds between checks

echo "[$(date)] Watchdog Panda started." >> "$LOG_FILE"

while true; do
    # Check if the process is running
    if ! pgrep -f "$TARGET_PROCESS" > /dev/null; then
        echo "[$(date)] Process '$TARGET_PROCESS' not found. Restarting..." >> "$LOG_FILE"
        
        # Attempt restart
        bash -c "$START_COMMAND" >> "$LOG_FILE" 2>&1
        
        echo "[$(date)] Restart command executed." >> "$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
