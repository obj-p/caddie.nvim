local M = {}

local MOTION_KEYS = { h = true, j = true, k = true, l = true, w = true, b = true, e = true, ge = true, f = true, F = true, t = true, T = true, ["0"] = true, ["$"] = true, ["^"] = true, gg = true, G = true }

local function split_keys(s)
  local out = {}
  local i = 1
  local n = #s
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

local function intent_contains_redacted(intent)
  for _, e in ipairs(intent.events) do
    if (e.kind == "edit" or e.kind == "write") and e.data and e.data.blob == vim.NIL then
      return true
    end
  end
  return false
end

function M.segment(events)
  local intents = {}
  local current = { id = nil, events = {}, dirty = false }
  local function flush()
    if #current.events > 0 then
      current.id = string.format("intent-%04d", #intents + 1)
      table.insert(intents, current)
    end
    current = { id = nil, events = {}, dirty = false }
  end
  for _, e in ipairs(events) do
    table.insert(current.events, e)
    if e.kind == "edit" then
      current.dirty = true
    elseif e.kind == "mode" and e.data and e.data.to == "n" and current.dirty then
      flush()
    elseif e.kind == "write" then
      flush()
    elseif e.kind == "cmd" then
      flush()
    end
  end
  flush()
  return intents
end

function M.analyze(intent)
  local keys_total = 0
  local motion_hist = {}
  local hjkl_runs = {}
  local current_run = 0
  local undos = 0
  local redos = 0
  local last_t = nil
  local idle_ms = 0
  local mode_trace = {}
  local keys_string = {}
  local normal_keys = {}
  local mode = "n"

  for _, e in ipairs(intent.events) do
    if e.kind == "mode" and e.data then
      table.insert(mode_trace, e.data.to)
      mode = e.data.to
    elseif e.kind == "key" and e.data and e.data.keys then
      local pieces = split_keys(e.data.keys)
      for _, k in ipairs(pieces) do
        keys_total = keys_total + 1
        table.insert(keys_string, k)
        if mode == "n" or mode == "v" or mode == "V" then
          table.insert(normal_keys, k)
          if MOTION_KEYS[k] then
            motion_hist[k] = (motion_hist[k] or 0) + 1
          end
          if k == "h" or k == "j" or k == "k" or k == "l" then
            current_run = current_run + 1
          else
            if current_run >= 2 then
              table.insert(hjkl_runs, current_run)
            end
            current_run = 0
          end
          if k == "u" then
            undos = undos + 1
          elseif k == "<C-r>" then
            redos = redos + 1
          end
        else
          if current_run >= 2 then
            table.insert(hjkl_runs, current_run)
          end
          current_run = 0
        end
      end
      if last_t and e.t - last_t > 1000 then
        idle_ms = idle_ms + (e.t - last_t)
      end
      last_t = e.t
    end
  end
  if current_run >= 2 then
    table.insert(hjkl_runs, current_run)
  end

  return {
    keys = keys_total,
    motion_hist = motion_hist,
    hjkl_runs = hjkl_runs,
    undo_ratio = keys_total > 0 and undos / keys_total or 0,
    redo_count = redos,
    idle_ms = idle_ms,
    mode_trace = mode_trace,
    keys_string = table.concat(keys_string),
    normal_keys = table.concat(normal_keys),
  }
end

local function suggestion(intent, severity, current_keys, suggested_keys, explanation, suggested_exec, title)
  local last_edit
  for _, e in ipairs(intent.events) do
    if e.kind == "edit" then
      last_edit = e
    end
  end
  return {
    intent_id = intent.id,
    title = title,
    severity = severity,
    current_keys = current_keys,
    suggested_keys = suggested_keys,
    suggested_exec = suggested_exec,
    explanation = explanation,
    buf = last_edit and last_edit.buf or vim.NIL,
    line_range = last_edit and { last_edit.data.first, last_edit.data.new_last } or vim.NIL,
  }
end

local function rule_hjkl_spam(intent, metrics)
  for _, run in ipairs(metrics.hjkl_runs) do
    if run >= 4 then
      return suggestion(intent, "medium", metrics.keys_string,
        "f{char} or w/b for word motion",
        "Run of " .. run .. " hjkl keys. Use f{char} for in-line jumps or w/b for word motion.",
        "w", "Repeated hjkl motion")
    end
  end
end

local function rule_arrow_in_insert(intent, metrics)
  local in_insert = false
  for _, e in ipairs(intent.events) do
    if e.kind == "mode" and e.data then
      in_insert = e.data.to == "i"
    elseif e.kind == "key" and in_insert and e.data then
      for _, k in ipairs(split_keys(e.data.keys)) do
        if k == "<Left>" or k == "<Right>" or k == "<Up>" or k == "<Down>" then
          return suggestion(intent, "low", metrics.keys_string,
            "<Esc> then motion",
            "Arrow key used in Insert mode. Exit to Normal with <Esc> and use h/j/k/l or word motions.",
            "<Esc>w", "Arrow keys in Insert mode")
        end
      end
    end
  end
end

local function rule_dd_then_p(intent, metrics)
  local s = metrics.normal_keys or ""
  if s:find("dd") and s:find("p", 1, true) then
    local _, ddend = s:find("dd")
    local pidx = s:find("p", ddend + 1, true)
    if pidx and pidx > ddend then
      return suggestion(intent, "low", metrics.keys_string,
        ":m for moving lines",
        "Sequence dd...p detected. Use :m to move a line directly without using a register.",
        ":m+1<CR>", "Delete then paste to move a line")
    end
  end
end

local function rule_xxxx_delete(intent, metrics)
  local run = 0
  for _, k in ipairs(split_keys(metrics.normal_keys or "")) do
    if k == "x" then
      run = run + 1
      if run >= 3 then
        return suggestion(intent, "low", metrics.keys_string,
          "dw, d$, or df{char}",
          "Run of x deletes. Use dw, d$, or df{char} for word, line-end, or char-bounded deletes.",
          "dw", "Repeated x deletes")
      end
    else
      run = 0
    end
  end
end

local function rule_slow_search(intent, metrics)
  local runs = 0
  for _, run in ipairs(metrics.hjkl_runs) do
    if run >= 6 then
      runs = runs + 1
    end
  end
  if runs >= 2 then
    return suggestion(intent, "low", metrics.keys_string,
      "/pattern or *",
      "Multiple long motion runs detected. Use /pattern or * to jump to a known string.",
      "*", "Long motion runs to navigate")
  end
end

M.rules = {
  ["hjkl-spam"] = rule_hjkl_spam,
  ["arrow-in-insert"] = rule_arrow_in_insert,
  ["dd-then-p"] = rule_dd_then_p,
  ["xxxx-delete"] = rule_xxxx_delete,
  ["slow-search"] = rule_slow_search,
}

function M.run_rules(intent, metrics)
  local out = {}
  for _, rule in pairs(M.rules) do
    local s = rule(intent, metrics)
    if s then
      table.insert(out, s)
    end
  end
  return out
end

function M.is_redacted_intent(intent)
  return intent_contains_redacted(intent)
end

return M
