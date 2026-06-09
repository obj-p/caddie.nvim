local M = {}

local function buf_summary(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    name = "[no name #" .. buf .. "]"
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, math.min(line_count, 60), false)
  local marks = {}
  local ann_ns = pcall(require, "caddie.annotations") and require("caddie.annotations").namespace() or nil
  if ann_ns then
    local raw = vim.api.nvim_buf_get_extmarks(buf, ann_ns, 0, -1, { details = true })
    for _, m in ipairs(raw) do
      local id, row, col, details = m[1], m[2], m[3], m[4]
      table.insert(marks, {
        id = id,
        row = row,
        col = col,
        virt_text = details and details.virt_text,
        sign_text = details and details.sign_text,
        sign_hl = details and details.sign_hl_group,
      })
    end
  end
  return {
    buf = buf,
    name = name,
    lines = lines,
    line_count = line_count,
    marks = marks,
    filetype = vim.api.nvim_get_option_value("filetype", { buf = buf }),
    buftype = vim.api.nvim_get_option_value("buftype", { buf = buf }),
  }
end

local function windows()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    table.insert(out, {
      win = win,
      buf = vim.api.nvim_win_get_buf(win),
      width = vim.api.nvim_win_get_width(win),
      height = vim.api.nvim_win_get_height(win),
      cursor = vim.api.nvim_win_get_cursor(win),
      statusline = pcall(vim.api.nvim_get_option_value, "statusline", { win = win })
        and vim.api.nvim_get_option_value("statusline", { win = win }) or "",
    })
  end
  return out
end

local function messages()
  local ok, msgs = pcall(vim.api.nvim_exec2, "messages", { output = true })
  if ok and msgs and msgs.output then
    local lines = vim.split(msgs.output, "\n", { plain = true })
    if #lines > 30 then
      lines = { unpack(lines, #lines - 29) }
    end
    return lines
  end
  return {}
end

local function caddie_state()
  local store = require("caddie.store")
  local annotations = require("caddie.annotations")
  return {
    recording = store.active ~= nil,
    session = store.active and {
      id = store.active.id,
      dir = store.active.dir,
      events_path = store.active.events_path,
      blobs_dir = store.active.blobs_dir,
    } or nil,
    annotations_visible = annotations.is_visible(),
    suggestions_loaded = #(annotations._suggestions or {}),
  }
end

function M.run()
  local snapshot = {
    mode = vim.api.nvim_get_mode(),
    cwd = vim.fn.getcwd(),
    windows = windows(),
    buffers = {},
    caddie = caddie_state(),
    messages = messages(),
  }
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      table.insert(snapshot.buffers, buf_summary(buf))
    end
  end
  return vim.inspect(snapshot)
end

return M
