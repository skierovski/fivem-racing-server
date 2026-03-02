#!/bin/bash
# Restart the FiveM server gracefully
# Called by GitHub Actions deploy and by cron for scheduled restarts

FIVEM_DIR="/opt/fivem"
SERVER_DATA="$FIVEM_DIR/server-data"
PID_FILE="$FIVEM_DIR/fivem.pid"

echo "[deploy] Stopping FiveM server..."

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        sleep 5
        if kill -0 "$PID" 2>/dev/null; then
            kill -9 "$PID"
            sleep 2
        fi
    fi
    rm -f "$PID_FILE"
fi

pkill -f "FXServer" 2>/dev/null || true
sleep 2

echo "[deploy] Starting FiveM server..."

cd "$FIVEM_DIR"
nohup ./run.sh +exec "$SERVER_DATA/server.cfg" > "$FIVEM_DIR/server.log" 2>&1 &
echo $! > "$PID_FILE"

echo "[deploy] FiveM server started (PID: $(cat $PID_FILE))"
