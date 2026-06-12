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

  local _, events_path, review_path = find_active_session()
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
    if e.kind == "write" and e.buf and e.data and e.data.path then
      buf_to_path[e.buf] = e.data.path
    end
  end

  local intents = rules.segment(events)
  local all_suggestions = {}
  local agent_input = {}

  for _, intent in ipairs(intents) do
    local metrics = rules.analyze(intent)
    for _, s in ipairs(rules.run_rules(intent, metrics)) do
      table.insert(all_suggestions, s)
    end
    if not rules.is_redacted_intent(intent) then
      table.insert(agent_input, { intent = intent, metrics = metrics })
    end
  end

  local function finish()
    for _, s in ipairs(all_suggestions) do
      if s.buf and s.buf ~= vim.NIL then
        s.path = buf_to_path[s.buf]
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

    return all_suggestions, review_path
  end

  if #agent_input > 0 and not opts.skip_agent then
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
