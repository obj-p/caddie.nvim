local M = {}

math.randomseed(os.time() + (vim.uv and vim.uv.hrtime() % 1e9 or 0))

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

local function iso_now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function nvim_version()
  local v = vim.version()
  return string.format("%d.%d.%d", v.major, v.minor, v.patch)
end

local function write_meta(path, meta)
  local f = io.open(path, "w")
  if not f then
    return
  end
  f:write(vim.fn.json_encode(meta))
  f:close()
end

local function wipe_sessions(data_dir)
  if vim.fn.isdirectory(data_dir) == 0 then
    return
  end
  for _, name in ipairs(vim.fn.readdir(data_dir)) do
    vim.fn.delete(data_dir .. "/" .. name, "rf")
  end
end

function M.start_session(data_dir, redact_globs)
  if M.active then
    return M.active
  end
  wipe_sessions(data_dir)
  local id = new_session_id()
  local dir = data_dir .. "/" .. id
  local blobs_dir = dir .. "/blobs"
  ensure_dir(dir)
  ensure_dir(blobs_dir)
  local events_path = dir .. "/events.jsonl"
  local meta_path = dir .. "/meta.json"
  local meta = {
    id = id,
    start_time = iso_now(),
    nvim_version = nvim_version(),
    cwd = vim.fn.getcwd(),
  }
  write_meta(meta_path, meta)
  M.active = {
    id = id,
    dir = dir,
    events_path = events_path,
    meta_path = meta_path,
    review_path = dir .. "/review.json",
    blobs_dir = blobs_dir,
    start_ns = vim.uv.hrtime(),
    redact_globs = redact_globs or {},
    fd = io.open(events_path, "a"),
    meta = meta,
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
  M.active.meta.end_time = iso_now()
  write_meta(M.active.meta_path, M.active.meta)
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
