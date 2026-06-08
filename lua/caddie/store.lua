local M = {}

M.active = nil

local function ensure_dir(path)
  vim.fn.mkdir(path, "p")
end

local function basename_matches(path, globs)
  if not path or path == "" then
    return false
  end
  local name = vim.fn.fnamemodify(path, ":t")
  for _, glob in ipairs(globs) do
    if vim.fn.match(name, vim.fn.glob2regpat(glob)) >= 0 then
      return true
    end
  end
  return false
end

local function new_session_id()
  return os.date("%Y%m%d-%H%M%S") .. "-" .. string.format("%06x", math.random(0, 0xffffff))
end

function M.start_session(data_dir, redact_globs)
  if M.active then
    return M.active
  end
  math.randomseed(os.time())
  local id = new_session_id()
  local dir = data_dir .. "/" .. id
  ensure_dir(dir)
  ensure_dir(dir .. "/blobs")
  local events_path = dir .. "/events.jsonl"
  M.active = {
    id = id,
    dir = dir,
    events_path = events_path,
    blobs_dir = dir .. "/blobs",
    start_ns = vim.uv.hrtime(),
    redact_globs = redact_globs or {},
    fd = io.open(events_path, "a"),
  }
  return M.active
end

function M.stop_session()
  if not M.active then
    return
  end
  if M.active.fd then
    M.active.fd:close()
  end
  M.active = nil
end

function M.now_ms()
  if not M.active then
    return 0
  end
  return math.floor((vim.uv.hrtime() - M.active.start_ns) / 1e6)
end

function M.write_event(event)
  if not M.active or not M.active.fd then
    return
  end
  M.active.fd:write(vim.fn.json_encode(event) .. "\n")
  M.active.fd:flush()
end

function M.is_redacted(path)
  if not M.active then
    return false
  end
  return basename_matches(path, M.active.redact_globs)
end

function M.write_blob(content)
  if not M.active then
    return nil
  end
  local hash = vim.fn.sha256(content)
  local path = M.active.blobs_dir .. "/" .. hash
  if vim.fn.filereadable(path) == 0 then
    local f = io.open(path, "w")
    if f then
      f:write(content)
      f:close()
    end
  end
  return hash
end

return M
