local M = {}

function M.setup(opts)
  local config = require("caddie.config")
  config.apply(opts)
  if config.current.autostart then
    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = function()
        require("caddie.recorder").start()
      end,
    })
  end
end

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

local function find_active_session()
  local store = require("caddie.store")
  if store.active then
    return store.active.dir, store.active.events_path, store.active.review_path
  end
  local config = require("caddie.config")
  if vim.fn.isdirectory(config.current.data_dir) == 0 then
    return
  end
  local entries = vim.fn.readdir(config.current.data_dir)
  table.sort(entries)
  for i = #entries, 1, -1 do
    local name = entries[i]
    if name ~= "blobs" then
      local dir = config.current.data_dir .. "/" .. name
      if vim.fn.isdirectory(dir) == 1 then
        return dir, dir .. "/events.jsonl", dir .. "/review.json"
      end
    end
  end
end

function M.review(opts)
  opts = opts or {}
  local config = require("caddie.config")
  local rules = require("caddie.rules")
  local agent = require("caddie.agent")

  if M._reviewing then
    vim.notify("caddie: a review is already running", vim.log.levels.WARN)
    return
  end

  local session_dir, events_path, review_path = find_active_session()
  if not events_path or vim.fn.filereadable(events_path) == 0 then
    vim.notify("caddie: no session found", vim.log.levels.WARN)
    return
  end

  local events = read_events(events_path)
  if opts.last_n_min and opts.last_n_min > 0 then
    local cutoff = events[#events] and events[#events].t - opts.last_n_min * 60000 or 0
    local filtered = {}
    for _, e in ipairs(events) do
      if e.t >= cutoff then
        table.insert(filtered, e)
      end
    end
    events = filtered
  end

  local buf_to_path = {}
  for _, e in ipairs(events) do
    if (e.kind == "write" or e.kind == "edit") and e.buf and e.data and e.data.path and e.data.path ~= "" then
      buf_to_path[e.buf] = e.data.path
    end
  end

  local intents = rules.segment(events)
  local all_suggestions = {}
  local agent_input = {}
  local intent_edits = {}

  for _, intent in ipairs(intents) do
    if not rules.is_redacted_intent(intent) then
      local metrics = rules.analyze(intent)
      for _, s in ipairs(rules.run_rules(intent, metrics)) do
        table.insert(all_suggestions, s)
      end
      table.insert(agent_input, { intent = intent, metrics = metrics })
    end
    for _, e in ipairs(intent.events) do
      if e.kind == "edit" and e.data and e.data.blob and e.data.blob ~= vim.NIL then
        intent_edits[intent.id] = e.data
      end
    end
  end

  local function read_excerpt(edit, target_line)
    local f = io.open(session_dir .. "/blobs/" .. edit.blob, "r")
    if not f then
      return nil
    end
    local content = f:read("*a")
    f:close()
    local blob_lines = vim.split(content, "\n", { plain = true })
    local first = edit.first or 0
    local idx = 0
    if type(target_line) == "number" then
      idx = math.max(0, target_line - first)
    end
    local start = math.max(0, idx - 1)
    local excerpt = {}
    local has_content = false
    for i = start + 1, math.min(#blob_lines, start + 6) do
      if blob_lines[i] ~= "" then
        has_content = true
      end
      table.insert(excerpt, (first + i) .. "| " .. blob_lines[i])
    end
    if not has_content then
      return nil
    end
    return excerpt
  end

  local function finish()
    for _, s in ipairs(all_suggestions) do
      if s.buf and s.buf ~= vim.NIL then
        s.path = buf_to_path[s.buf]
      end
      local edit = s.intent_id and intent_edits[s.intent_id]
      if edit and not s.excerpt then
        local target = type(s.line_range) == "table" and s.line_range[1] or nil
        s.excerpt = read_excerpt(edit, target)
      end
    end

    local seen = {}
    local deduped = {}
    for _, s in ipairs(all_suggestions) do
      local key = (s.suggested_keys or "") .. "\0" .. (s.explanation or "")
      if not seen[key] then
        seen[key] = true
        table.insert(deduped, s)
      end
    end
    all_suggestions = deduped

    local f = io.open(review_path, "w")
    if f then
      f:write(vim.fn.json_encode(all_suggestions))
      f:close()
    end

    if config.current.annotations_enabled and not opts.skip_ui then
      require("caddie.annotations").refresh(all_suggestions)
    end
    if not opts.skip_ui then
      require("caddie.report").open(all_suggestions)
    end

    M._reviewing = false
    return all_suggestions, review_path
  end

  if #agent_input > 0 and not opts.skip_agent then
    M._reviewing = true
    vim.notify(string.format("caddie: reviewing %d intents...", #agent_input), vim.log.levels.INFO)
    local payload = agent.build_payload(agent_input)
    local result, result_path
    agent.send(payload, config.current.agent, function(suggestions, err)
      if suggestions then
        for _, s in ipairs(suggestions) do
          table.insert(all_suggestions, s)
        end
      elseif err then
        vim.notify("caddie agent: " .. err, vim.log.levels.WARN)
      end
      result, result_path = finish()
    end)
    return result, result_path
  end

  return finish()
end

return M
