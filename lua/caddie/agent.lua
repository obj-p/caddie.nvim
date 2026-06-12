local M = {}

local KEYS_CAP = 500

local SYSTEM_PROMPT = [[You are a Vim coach. Given a session split into intents,
each with metrics, a key sequence, mode trace, and a small buffer-change window,
return a JSON array of suggestions where each item has:
- intent_id (string)
- severity ("low" | "medium" | "high")
- current_keys (string)
- suggested_keys (string)
- explanation (string, one line)
- buf (number or null)
- line_range ([start, end] or null)
Only suggest motions and operators that exist in Vim today. Be terse.
Return strictly JSON, no prose.]]

local function build_intent_payload(intent, metrics)
  local keys = metrics.keys_string
  if #keys > KEYS_CAP then
    keys = keys:sub(1, KEYS_CAP) .. "...[truncated]"
  end
  local last_edit
  for _, e in ipairs(intent.events) do
    if e.kind == "edit" then
      last_edit = e
    end
  end
  return {
    id = intent.id,
    metrics = {
      keys = metrics.keys,
      motion_hist = metrics.motion_hist,
      hjkl_runs = metrics.hjkl_runs,
      undo_ratio = metrics.undo_ratio,
      idle_ms = metrics.idle_ms,
    },
    keys = keys,
    mode_trace = metrics.mode_trace,
    edit = last_edit and {
      buf = last_edit.buf,
      first = last_edit.data.first,
      new_last = last_edit.data.new_last,
    } or vim.NIL,
  }
end

M.build_payload = function(intents_with_metrics)
  local payload = {}
  for _, pair in ipairs(intents_with_metrics) do
    table.insert(payload, build_intent_payload(pair.intent, pair.metrics))
  end
  return payload
end

local function anthropic_call(payload, opts, cb)
  local key = os.getenv(opts.api_key_env or "ANTHROPIC_API_KEY")
  if not key or key == "" then
    cb(nil, "missing API key in $" .. (opts.api_key_env or "ANTHROPIC_API_KEY"))
    return
  end
  local body = vim.fn.json_encode({
    model = opts.model or "claude-opus-4-7",
    max_tokens = 4096,
    system = {
      { type = "text", text = SYSTEM_PROMPT, cache_control = { type = "ephemeral" } },
    },
    messages = {
      { role = "user", content = vim.fn.json_encode(payload) },
    },
  })
  local tmp = vim.fn.tempname()
  local f = io.open(tmp, "w")
  f:write(body)
  f:close()
  local cmd = {
    "curl", "-sS", "https://api.anthropic.com/v1/messages",
    "-H", "x-api-key: " .. key,
    "-H", "anthropic-version: 2023-06-01",
    "-H", "content-type: application/json",
    "--data-binary", "@" .. tmp,
  }
  vim.system(cmd, { text = true }, function(out)
    vim.schedule(function()
      os.remove(tmp)
      if out.code ~= 0 then
        cb(nil, "curl failed: " .. (out.stderr or ""))
        return
      end
      local result = out.stdout or ""
      local ok, decoded = pcall(vim.fn.json_decode, result)
      if not ok or not decoded.content then
        cb(nil, "bad response: " .. result)
        return
      end
      local text = decoded.content[1] and decoded.content[1].text or ""
      local ok2, suggestions = pcall(vim.fn.json_decode, text)
      if not ok2 then
        cb(nil, "agent returned non-JSON: " .. text)
        return
      end
      cb(suggestions)
    end)
  end)
end

local function build_claude_prompt(payload)
  return SYSTEM_PROMPT .. "\n\nIntents:\n" .. vim.fn.json_encode(payload)
end

local function strip_code_fence(s)
  local inner = s:match("```%w*\n(.-)\n```")
  if inner then
    return inner
  end
  return s
end

local function parse_claude_response(stdout)
  local ok, decoded = pcall(vim.fn.json_decode, stdout)
  if not ok or not decoded or not decoded.result then
    return nil, "bad claude cli response: " .. stdout
  end
  local body = strip_code_fence(vim.trim(decoded.result))
  local ok2, suggestions = pcall(vim.fn.json_decode, body)
  if not ok2 then
    return nil, "claude returned non-JSON suggestions: " .. decoded.result
  end
  return suggestions
end

local function claude_code_call(payload, _opts, cb)
  local prompt = build_claude_prompt(payload)
  vim.system({ "claude", "-p", "--output-format", "json" }, { stdin = prompt, text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        cb(nil, "claude cli failed: " .. (out.stderr or ""))
        return
      end
      cb(parse_claude_response(out.stdout or ""))
    end)
  end)
end

local function default_impl(payload, opts, cb)
  if opts.provider == "claude-code" then
    return claude_code_call(payload, opts, cb)
  end
  return anthropic_call(payload, opts, cb)
end

M._impl = default_impl
M._build_claude_prompt = build_claude_prompt
M._parse_claude_response = parse_claude_response

function M.set_implementation(fn)
  M._impl = fn or default_impl
end

function M.send(payload, opts, cb)
  local suggestions, err = M._impl(payload, opts or {}, cb)
  if suggestions ~= nil or err ~= nil then
    cb(suggestions, err)
  end
end

return M
