#!/usr/bin/env bash
set -euo pipefail

SOCK="${CADDIE_SPIKE_SOCK:-/tmp/caddie-spike.sock}"

nvim --server "$SOCK" --remote-expr "luaeval('require(\"caddie._spike_dump\").run()')"
