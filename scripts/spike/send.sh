#!/usr/bin/env bash
set -euo pipefail

SOCK="${CADDIE_SPIKE_SOCK:-/tmp/caddie-spike.sock}"

if [ "$#" -lt 1 ]; then
	echo "usage: $0 '<keys>'" >&2
	exit 1
fi

nvim --server "$SOCK" --remote-send "$1"
