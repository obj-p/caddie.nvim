#!/usr/bin/env bash
set -euo pipefail

SOCK="${CADDIE_SPIKE_SOCK:-/tmp/caddie-spike.sock}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="${CADDIE_SPIKE_LOG:-/tmp/caddie-spike.log}"
DATA_DIR="${CADDIE_SPIKE_DATA:-/tmp/caddie-spike-data}"

if [ -S "$SOCK" ]; then
	echo "spike server already running at $SOCK"
	exit 0
fi

rm -f "$SOCK"
mkdir -p "$DATA_DIR"

NVIM_APPNAME=caddie-spike nohup nvim --headless --clean \
	--listen "$SOCK" \
	--cmd "set rtp+=$REPO" \
	-c "lua require('caddie').setup({ data_dir = '$DATA_DIR', autostart = false, agent = { provider = 'claude-code' } })" \
	>"$LOG" 2>&1 &

for _ in $(seq 1 30); do
	if [ -S "$SOCK" ]; then
		echo "spike server up at $SOCK (log: $LOG, data: $DATA_DIR)"
		exit 0
	fi
	sleep 0.1
done

echo "failed to start spike server, see $LOG"
exit 1
