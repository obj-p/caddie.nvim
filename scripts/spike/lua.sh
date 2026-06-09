#!/usr/bin/env bash
set -euo pipefail

SOCK="${CADDIE_SPIKE_SOCK:-/tmp/caddie-spike.sock}"

if [ "$#" -lt 1 ]; then
	echo "usage: $0 '<lua-expr>'" >&2
	exit 1
fi

nvim --server "$SOCK" --remote-expr "luaeval(\"vim.inspect((function() $1 end)())\")"
