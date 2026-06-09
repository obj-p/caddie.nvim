#!/usr/bin/env bash
set -euo pipefail

SOCK="${CADDIE_SPIKE_SOCK:-/tmp/caddie-spike.sock}"

if [ ! -S "$SOCK" ]; then
	echo "no spike server running at $SOCK"
	exit 0
fi

nvim --server "$SOCK" --remote-expr "execute('qa!')" >/dev/null 2>&1 || true
rm -f "$SOCK"
echo "spike server stopped"
