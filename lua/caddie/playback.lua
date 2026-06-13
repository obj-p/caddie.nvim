local M = {}

local function split_keys(s)
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "<" then
      local j = s:find(">", i + 1, true)
      if j then
        table.insert(out, s:sub(i, j))
        i = j + 1
      else
        table.insert(out, c)
        i = i + 1
      end
    else
      table.insert(out, c)
      i = i + 1
    end
  end
  return out
end

function M.play(opts, on_done)
  opts = opts or {}
  local lines = opts.lines or {}
  local delay = opts.delay or 220
  local keys = opts.keys or ""

  local demo_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(demo_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = demo_buf })

  local width = 20
  for _, l in ipairs(lines) do
    width = math.max(width, #l + 2)
  end
  local height = math.max(#lines, 1)
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local demo_win = vim.api.nvim_open_win(demo_buf, true, {
    relative = "editor", row = row, col = col,
    width = width, height = height, style = "minimal", border = "rounded",
  })
  vim.api.nvim_win_set_cursor(demo_win, { math.min(opts.line or 1, height), 0 })

  local cast_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(cast_buf, 0, -1, false, { "" })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = cast_buf })
  local cast_win = vim.api.nvim_open_win(cast_buf, false, {
    relative = "editor", row = row + height + 1, col = col,
    width = width, height = 1, style = "minimal", border = "rounded",
  })

  local pieces = split_keys(keys)
  local shown = {}
  local i = 0
  local done = false

  local function close_cast()
    if vim.api.nvim_win_is_valid(cast_win) then
      vim.api.nvim_win_close(cast_win, true)
    end
  end

  local function finish()
    if done then
      return
    end
    done = true
    close_cast()
    if on_done then
      on_done(demo_buf, table.concat(shown, " "))
    end
  end

  vim.keymap.set("n", "q", function()
    done = true
    close_cast()
    if vim.api.nvim_win_is_valid(demo_win) then
      vim.api.nvim_win_close(demo_win, true)
    end
  end, { buffer = demo_buf })

  local function tick()
    if done then
      return
    end
    i = i + 1
    if i > #pieces then
      finish()
      return
    end
    table.insert(shown, pieces[i])
    if vim.api.nvim_buf_is_valid(cast_buf) then
      vim.api.nvim_buf_set_lines(cast_buf, 0, -1, false, { " " .. table.concat(shown, " ") })
    end
    if i == #pieces and vim.api.nvim_win_is_valid(demo_win) then
      vim.api.nvim_set_current_win(demo_win)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    end
    vim.defer_fn(tick, delay)
  end

  vim.defer_fn(tick, delay)
  return demo_buf
end

return M
