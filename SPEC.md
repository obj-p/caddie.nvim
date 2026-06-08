# caddie.nvim

A Neovim plugin that records every keystroke and edit of a session, then has an
agent review the session and suggest more efficient keystrokes. Like a golf
caddie watching your stroke count and recommending a better club.

## Goals

1. Record a complete, replayable timeline of a Neovim session.
2. Let an agent analyze the timeline and produce actionable suggestions to
   reduce keystrokes and use better Vim idioms.
3. Surface suggestions where the user will see them, as a report and as
   inline annotations on the affected lines.
4. Stay local-first, with no network traffic outside the optional agent call.

## Non-Goals (v1)

- Live coaching during typing.
- Multi-user collaboration or shared sessions.
- Proposing new mappings or snippets, only existing motions and operators.
- Pluggable storage backends.
- Pluggable agent backends beyond a thin interface with one Anthropic
  implementation.

## Configuration

Single setup entry: `require("caddie").setup(opts)`.

```lua
require("caddie").setup({
  data_dir = vim.fn.stdpath("data") .. "/caddie",
  autostart = true,
  auto_review_on_exit = false,
  annotations_enabled = true,
  redact_globs = { ".env", ".env.*", "*.pem", "*.key" },
  agent = {
    provider = "anthropic",
    model = "claude-opus-4-7",
    api_key_env = "ANTHROPIC_API_KEY",
  },
})
```

## Layer 1: Recording

### Captured Events

| Source                          | Produces           | Notes                                  |
| ------------------------------- | ------------------ | -------------------------------------- |
| `vim.on_key()`                  | `key` events       | Translated via `vim.fn.keytrans()`.    |
| `ModeChanged` autocmd           | `mode` events      | Captures every mode transition.        |
| `CursorMoved`, `CursorMovedI`   | cursor samples     | Debounced to 50ms, attached to events. |
| `nvim_buf_attach` `on_lines`    | `edit` events      | Per-change line ranges.                |
| `BufWritePost`                  | `write` events     | Path plus content hash.                |
| `CmdlineLeave`, macro playback  | `cmd` events       | Separates ex commands and macros.      |

### Event Schema (JSONL)

One event per line, shape:

```json
{ "t": 12345, "kind": "key|mode|edit|write|cmd", "buf": 3, "data": { ... } }
```

- `t` is monotonic milliseconds since session start.
- `kind` is one of `key`, `mode`, `edit`, `write`, `cmd`.
- `buf` is the buffer id at event time, or `null` for global events.
- `data` is kind-specific:
  - `key`: `{ "keys": "<Esc>dw" }`
  - `mode`: `{ "from": "i", "to": "n" }`
  - `edit`: `{ "first": 12, "last": 14, "new_last": 13, "blob": "<sha256>" }`
  - `write`: `{ "path": "/abs/path", "blob": "<sha256>" }`
  - `cmd`: `{ "type": "ex|macro", "text": "%s/foo/bar/g" }`

### Redaction

When the buffer's filename matches any glob in `redact_globs`, `edit` and
`write` events store `blob: null` and the snapshot is not written.

## Layer 2: Storage

### Layout

```
~/.local/share/nvim/caddie/
└── <session-id>/
    ├── meta.json       # start time, nvim version, cwd, end time
    ├── events.jsonl    # append-only event stream
    ├── blobs/          # buffer snapshots, content-addressed
    │   └── <sha256>
    └── review.json     # agent output, written after :CaddieReview
```

### Session ID

Format: `YYYYMMDD-HHMMSS-<6char>`. Sorts chronologically in `ls`. The 6 char
suffix avoids collisions on rapid restarts.

### Blob Deduplication

Buffer snapshots are written to `blobs/<sha256>` where the hash is computed
over the snapshot content. Identical snapshots across sessions share one
file when sessions live under the same `data_dir`.

## Layer 3: Agent Review

### Intent Segmentation

The event stream is split into "intents." An intent is the slice of events
between two entries into Normal mode that follow a buffer change. A
`BufWritePost` event always hard-splits intents. Each intent represents one
"the user wanted to do X" unit.

### Pre-Analysis (Lua side)

For each intent compute, deterministically:

- Keystroke count.
- Motion histogram, counts of `h`, `j`, `k`, `l`, `w`, `b`, `f`, `t`, etc.
- Repeated `hjkl` runs (length per run).
- Undo/redo ratio.
- Idle time within the intent.

These metrics travel with the intent in the agent prompt. They also feed the
built-in rule set.

### Built-In Rules

Run before the agent. Cover the most common anti-patterns so the plugin is
useful offline.

| Rule              | Detects                                 | Suggests                   |
| ----------------- | --------------------------------------- | -------------------------- |
| `hjkl-spam`       | 4+ consecutive `h/j/k/l`                | `f{char}`, `w/b`, `gg/G`   |
| `arrow-in-insert` | Arrow keys while in Insert mode         | `<Esc>` then motion        |
| `dd-then-p`       | `dd` followed by navigation then `p`    | `:m` to move the line      |
| `xxxx-delete`     | 3+ consecutive `x`                      | `dw`, `d$`, `df{char}`     |
| `slow-search`     | Manual scrolling to find a known string | `/pattern` or `*`          |

### Agent Call

One call per session. Uses the Anthropic API with prompt caching on the
system prompt (Vim idiom rubric).

Request payload, per intent:

```json
{
  "id": "intent-0001",
  "metrics": { "keys": 17, "motion_hist": { "h": 8, "j": 4 }, "undo_ratio": 0.0 },
  "keys": "8hjjjjdwidone<Esc>",
  "mode_trace": ["n", "n", "i", "n"],
  "buffer_window": {
    "path": "src/foo.lua",
    "before": [{ "line": 12, "text": "  return false" }],
    "after":  [{ "line": 12, "text": "  return done" }]
  }
}
```

### Suggestion Schema (agent output)

JSON array, each item:

```json
{
  "intent_id": "intent-0001",
  "severity": "low|medium|high",
  "current_keys": "8hjjjjdwidone<Esc>",
  "suggested_keys": "Fhcwdone<Esc>",
  "explanation": "Use F<char> to jump back to the target instead of counting h.",
  "buf": 3,
  "line_range": [12, 12]
}
```

## Layer 4: Output and UX

### Commands

| Command                         | Action                                              |
| ------------------------------- | --------------------------------------------------- |
| `:CaddieStart`                  | Begin recording a new session.                      |
| `:CaddieStop`                   | Stop recording and finalize `meta.json`.            |
| `:CaddieReview [last_n_min]`    | Run rules plus agent on the active session.         |
| `:CaddieReplay`                 | Open `vim.ui.select` over past sessions and step.   |
| `:CaddieToggleAnnotations`      | Show or hide inline suggestion virtual text.        |

### Report Buffer

`:CaddieReview` opens a scratch buffer in a right split with filetype
`markdown`. Sections are ordered by severity then time. Each suggestion shows
current keys, suggested keys, a one line why, and a `gf`-jumpable
`path:line` anchor.

### Inline Annotations

For each suggestion, place an extmark at the end of the affected line using
`nvim_buf_set_extmark` with virtual text in highlight group `CaddieHint`.
Place a sign in the gutter colored by severity. Annotations auto-refresh
after each `:CaddieReview`. `:CaddieToggleAnnotations` controls visibility
only.

### Replay

`:CaddieReplay` picks a session via `vim.ui.select`, opens the recorded
buffer state at `t=0` in a scratch buffer, and steps through events with
`]r` and `[r`. The pressed key is shown in the statusline. Cursor moves and
edits animate as they replay. Stepping is per-event, not per-time-unit, so
the user can pause to think.

## Layer 5: Plugin Layout

### Repository Structure

```
caddie.nvim/
├── lua/
│   └── caddie/
│       ├── init.lua          # setup, public API
│       ├── config.lua        # defaults plus user opts merge
│       ├── recorder.lua      # on_key, autocmds, on_lines
│       ├── store.lua         # session dirs, events.jsonl, blobs
│       ├── rules.lua         # built-in anti-pattern detectors
│       ├── agent.lua         # agent interface plus Anthropic impl
│       ├── report.lua        # markdown scratch buffer
│       ├── annotations.lua   # extmarks plus signs
│       └── replay.lua        # session replay engine
├── plugin/
│   └── caddie.lua            # command registration
├── tests/                    # plenary.nvim busted specs
├── Makefile                  # `make test`
├── README.md
└── SPEC.md
```

### Dependencies

- Hard: none.
- Soft runtime: `curl` for the agent HTTP call, any picker that implements
  `vim.ui.select`.
- Dev: `plenary.nvim` for tests.

### Distribution

Published on GitHub. Installable with lazy.nvim and packer.

### CI

GitHub Action matrix runs `make test` against Neovim stable and nightly on
each push.

## Open for v2

- Live coaching during typing, with a debounce window.
- Pluggable storage (SQLite, sync to a server).
- Pluggable agent backends beyond Anthropic (Ollama, OpenAI).
- Proposing new mappings, snippets, or text objects when a pattern recurs.
- Cross-session analysis to track skill growth over weeks.
- Treesitter context in the prompt (intent like "rename function" inferred
  from AST).

## Acceptance Criteria

- `:CaddieStart` followed by typing creates `events.jsonl` with at least one
  event per kind across a representative editing session.
- Replay reproduces the buffer state at any event index within a 1 line
  delta of the original.
- `:CaddieReview` on a session of fewer than 200 intents returns within
  10 seconds end to end (rules plus agent).
- At least one built-in rule (e.g., `hjkl-spam`) fires correctly on a
  hand-crafted session without any agent call.
- Annotations appear at the correct `(buf, line)` and survive buffer edits.
- Redaction prevents `.env` content from being stored in `blobs/`.
