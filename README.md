# caddie.nvim

A Neovim plugin that records your editing session and has an agent review your
keystrokes, suggesting more efficient ones. Like a golf caddie for vim.

See [SPEC.md](SPEC.md) for the full design and [issue #1](https://github.com/obj-p/caddie.nvim/issues/1) for the build plan.

## Status

Pre-alpha. Commands register but are not yet implemented.

## Install

With lazy.nvim:

```lua
{
  "obj-p/caddie.nvim",
  opts = {},
}
```

## Commands

| Command                       | Description                                      |
| ----------------------------- | ------------------------------------------------ |
| `:CaddieStart`                | Begin recording a new session.                   |
| `:CaddieStop`                 | Stop recording.                                  |
| `:CaddieReview [last_n_min]`  | Run rules plus agent on the active session.      |
| `:CaddieReplay`               | Step through a past session.                     |
| `:CaddieToggleAnnotations`    | Show or hide inline suggestion virtual text.     |

## Configuration

Defaults shown.

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

## Development

```sh
make test
```
