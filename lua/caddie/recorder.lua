local M = {}

local store = require("caddie.store")
local config = require("caddie.config")

local CURSOR_DEBOUNCE_MS = 50

local state = {
  augroup = nil,
  on_key_ns = nil,
  attached = {},
  cursor_timer = nil,
  last_macro = "",
  cmdline_text = "",
}

local function emit(kind, buf, data)
  store.write_event({
    t = store.now_ms(),
    kind = kind,
    buf = buf,
    data = data,
  })
end

local function on_lines(_, buf, _, first, last, new_last)
  if not store.active then
    return true
  end
  local path = vim.api.nvim_buf_get_name(buf)
  local blob = vim.NIL
  if not store.is_redacted(path) then
    local lines = vim.api.nvim_buf_get_lines(buf, first, new_last, false)
    blob = store.write_blob(table.concat(lines, "\n"))
  end
  emit("edit", buf, { first = first, last = last, new_last = new_last, blob = blob })
end

local function attach_buffer(buf)
  if state.attached[buf] or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  state.attached[buf] = true
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = on_lines,
    on_detach = function(_, b)
      state.attached[b] = nil
    end,
  })
end

function M.start()
  if store.active then
    return
  end
  store.start_session(config.current.data_dir, config.current.redact_globs)
  vim.notify("caddie: recording started", vim.log.levels.INFO)
  state.augroup = vim.api.nvim_create_augroup("caddie_recorder", { clear = true })

  state.on_key_ns = vim.on_key(function(_, typed)
    if not store.active then
      return
    end
    local keys = vim.fn.keytrans(typed or "")
    if keys == "" then
      return
    end
    if store.is_redacted(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())) then
      return
    end
    local executing = vim.fn.reg_executing()
    if executing ~= "" and executing ~= state.last_macro then
      state.last_macro = executing
      emit("cmd", nil, { type = "macro", text = "@" .. executing })
    elseif executing == "" then
      state.last_macro = ""
    end
    emit("key", vim.api.nvim_get_current_buf(), { keys = keys })
  end)

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = state.augroup,
    callback = function(args)
      local from, to = args.match:match("([^:]+):(.+)")
      emit("mode", vim.api.nvim_get_current_buf(), { from = from, to = to })
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = state.augroup,
    callback = function()
      if state.cursor_timer then
        return
      end
      state.cursor_timer = vim.defer_fn(function()
        state.cursor_timer = nil
      end, CURSOR_DEBOUNCE_MS)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufNewFile", "BufReadPost" }, {
    group = state.augroup,
    callback = function(args)
      attach_buffer(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = state.augroup,
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      local blob = vim.NIL
      if not store.is_redacted(path) then
        local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
        blob = store.write_blob(table.concat(lines, "\n"))
      end
      emit("write", args.buf, { path = path, blob = blob })
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineChanged", {
    group = state.augroup,
    callback = function()
      state.cmdline_text = vim.fn.getcmdline()
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = state.augroup,
    callback = function(args)
      if args.match == ":" and state.cmdline_text ~= "" then
        emit("cmd", nil, { type = "ex", text = state.cmdline_text })
      end
      state.cmdline_text = ""
    end,
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      attach_buffer(buf)
    end
  end
end

function M.stop()
  if not store.active then
    return
  end
  if state.augroup then
    vim.api.nvim_del_augroup_by_id(state.augroup)
    state.augroup = nil
  end
  if state.on_key_ns then
    vim.on_key(nil, state.on_key_ns)
    state.on_key_ns = nil
  end
  state.attached = {}
  state.last_macro = ""
  state.cmdline_text = ""
  store.stop_session()
  vim.notify("caddie: recording stopped", vim.log.levels.INFO)
end

function M.is_recording()
  return store.active ~= nil
end

return M
