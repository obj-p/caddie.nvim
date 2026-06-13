local M = {}

local state = {
  buf = nil,
  events = nil,
  idx = 0,
  blobs_dir = nil,
}

local function read_events(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then
    return out
  end
  for line in f:lines() do
    if line ~= "" then
      table.insert(out, vim.fn.json_decode(line))
    end
  end
  f:close()
  return out
end

local function read_blob(hash)
  if not hash or hash == vim.NIL or not state.blobs_dir then
    return nil
  end
  local f = io.open(state.blobs_dir .. "/" .. hash, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function update_statusline()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local cur = state.events[state.idx]
  local label = ""
  if cur then
    label = cur.kind .. " " .. (cur.data and (cur.data.keys or cur.data.text or cur.data.path or "") or "")
  end
  pcall(vim.api.nvim_set_option_value, "statusline",
    string.format("caddie replay [%d/%d] %s", state.idx, #state.events, label),
    { win = vim.fn.bufwinid(state.buf) })
end

local function rebuild_to(target)
  if not state.buf or not state.events then
    return
  end
  target = math.max(0, math.min(target, #state.events))
  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {})
  for i = 1, target do
    local e = state.events[i]
    if e.kind == "edit" and e.data then
      local content = read_blob(e.data.blob) or ""
      local lines = vim.split(content, "\n", { plain = true })
      pcall(vim.api.nvim_buf_set_lines, state.buf, e.data.first, e.data.last, false, lines)
    end
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
  state.idx = target
  update_statusline()
end

function M.start(session_dir)
  state.blobs_dir = session_dir .. "/blobs"
  state.events = read_events(session_dir .. "/events.jsonl")
  state.idx = 0
  vim.cmd("tabnew")
  state.buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.buf })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.buf })
  pcall(vim.api.nvim_buf_set_name, state.buf, "caddie://replay/" .. vim.fn.fnamemodify(session_dir, ":t"))
  vim.keymap.set("n", "]r", function() M.step(1) end, { buffer = state.buf })
  vim.keymap.set("n", "[r", function() M.step(-1) end, { buffer = state.buf })
  rebuild_to(0)
end

function M.step(delta)
  if not state.events then
    return
  end
  rebuild_to(state.idx + delta)
end

function M.goto_index(i)
  rebuild_to(i)
end

function M.current_index()
  return state.idx
end

function M.event_count()
  return state.events and #state.events or 0
end

function M.list_sessions()
  local config = require("caddie.config")
  if vim.fn.isdirectory(config.current.data_dir) == 0 then
    return {}
  end
  local entries = vim.fn.readdir(config.current.data_dir)
  table.sort(entries)
  local out = {}
  for _, name in ipairs(entries) do
    if name ~= "blobs" then
      local dir = config.current.data_dir .. "/" .. name
      if vim.fn.isdirectory(dir) == 1 then
        table.insert(out, { id = name, dir = dir })
      end
    end
  end
  return out
end

function M.pick()
  local sessions = M.list_sessions()
  if #sessions == 0 then
    vim.notify("caddie: no sessions found", vim.log.levels.WARN)
    return
  end
  vim.ui.select(sessions, {
    prompt = "Pick a session to replay",
    format_item = function(s) return s.id end,
  }, function(choice)
    if choice then
      M.start(choice.dir)
    end
  end)
end

return M
