describe("review", function()
  local caddie, store, agent, recorder, tmpdir

  before_each(function()
    package.loaded["caddie"] = nil
    package.loaded["caddie.config"] = nil
    package.loaded["caddie.store"] = nil
    package.loaded["caddie.recorder"] = nil
    package.loaded["caddie.rules"] = nil
    package.loaded["caddie.agent"] = nil
    tmpdir = vim.fn.tempname()
    caddie = require("caddie")
    caddie.setup({ data_dir = tmpdir, autostart = false })
    store = require("caddie.store")
    recorder = require("caddie.recorder")
    agent = require("caddie.agent")
  end)

  after_each(function()
    recorder.stop()
    agent.set_implementation(nil)
  end)

  local function write_events(events)
    local session = store.start_session(tmpdir, {})
    for _, e in ipairs(events) do
      store.write_event(e)
    end
    store.stop_session()
    return session
  end

  it("runs hjkl-spam without an agent call", function()
    local session = write_events({
      { t = 0, kind = "key", buf = 1, data = { keys = "jjjjj" } },
      { t = 1, kind = "edit", buf = 1, data = { first = 4, last = 4, new_last = 4, blob = "x" } },
      { t = 2, kind = "mode", buf = 1, data = { from = "i", to = "n" } },
    })
    local called = false
    agent.set_implementation(function() called = true; return {} end)

    local suggestions = caddie.review({ skip_agent = true })
    assert.is_not_nil(suggestions)
    assert.is_true(#suggestions > 0)
    assert.is_false(called)

    local f = io.open(session.review_path, "r")
    assert.is_not_nil(f)
    f:close()
  end)

  it("resolves suggestion path from edit events without a write", function()
    write_events({
      { t = 0, kind = "key", buf = 1, data = { keys = "xxxx" } },
      { t = 1, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = 1, blob = "x", path = "/tmp/foo.lua" } },
      { t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } },
    })
    agent.set_implementation(function() return {} end)
    local suggestions = caddie.review({ skip_ui = true })
    local s = suggestions[1]
    assert.is_not_nil(s)
    assert.equals("/tmp/foo.lua", s.path)
  end)

  it("skips rule suggestions for redacted intents", function()
    write_events({
      { t = 0, kind = "key", buf = 1, data = { keys = "jjjjj" } },
      { t = 1, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = 1, blob = vim.NIL } },
      { t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } },
    })
    agent.set_implementation(function() return {} end)
    local suggestions = caddie.review({ skip_ui = true })
    assert.equals(0, #suggestions)
  end)

  it("does not emit a file error when reviewing with no data dir", function()
    vim.cmd("messages clear")
    local result = caddie.review()
    assert.is_nil(result)
    local msgs = vim.fn.execute("messages")
    assert.is_nil(msgs:find("E484"))
  end)

  it("ignores a second review while one is in flight", function()
    write_events({
      { t = 0, kind = "key", buf = 1, data = { keys = "jjjjj" } },
      { t = 1, kind = "edit", buf = 1, data = { first = 4, last = 4, new_last = 4, blob = "x" } },
      { t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } },
    })
    local calls = 0
    agent.set_implementation(function(_, _, _)
      calls = calls + 1
    end)
    caddie.review({ skip_ui = true })
    caddie.review({ skip_ui = true })
    assert.equals(1, calls)
  end)

  it("omits the excerpt for an empty deletion window", function()
    store.start_session(tmpdir, {})
    local hash = store.write_blob("")
    store.write_event({ t = 0, kind = "key", buf = 1, data = { keys = "jjjjj" } })
    store.write_event({ t = 1, kind = "edit", buf = 1, data = { first = 4, last = 8, new_last = 4, blob = hash } })
    store.write_event({ t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } })
    store.stop_session()
    agent.set_implementation(function() return {} end)
    local suggestions = caddie.review({ skip_ui = true })
    assert.is_true(#suggestions > 0)
    for _, s in ipairs(suggestions) do
      assert.is_nil(s.excerpt)
    end
  end)

  it("centers the excerpt on the suggested line", function()
    store.start_session(tmpdir, {})
    local body = {}
    for i = 1, 10 do
      body[i] = "L" .. i
    end
    local hash = store.write_blob(table.concat(body, "\n"))
    store.write_event({ t = 0, kind = "key", buf = 1, data = { keys = "x" } })
    store.write_event({ t = 1, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = 10, blob = hash } })
    store.write_event({ t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } })
    store.stop_session()
    agent.set_implementation(function()
      return { { intent_id = "intent-0001", severity = "high", current_keys = "x",
        suggested_keys = "dd", explanation = "e", line_range = { 7, 8 } } }
    end)
    local suggestions = caddie.review({ skip_ui = true })
    local agent_sug
    for _, s in ipairs(suggestions) do
      if s.suggested_keys == "dd" then
        agent_sug = s
      end
    end
    assert.is_not_nil(agent_sug)
    assert.is_not_nil(agent_sug.excerpt)
    local joined = table.concat(agent_sug.excerpt, "\n")
    assert.is_true(joined:find("8| L8", 1, true) ~= nil)
    assert.is_nil(joined:find("1| L1", 1, true))
  end)

  it("excludes redacted intents from agent payload", function()
    write_events({
      { t = 0, kind = "key", buf = 1, data = { keys = "i" } },
      { t = 1, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = 1, blob = vim.NIL } },
      { t = 2, kind = "mode", buf = 1, data = { from = "i", to = "n" } },
      { t = 3, kind = "key", buf = 1, data = { keys = "a" } },
      { t = 4, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = 1, blob = "abc" } },
      { t = 5, kind = "mode", buf = 1, data = { from = "i", to = "n" } },
    })
    local received_payload
    agent.set_implementation(function(payload)
      received_payload = payload
      return {}
    end)
    caddie.review()
    assert.is_not_nil(received_payload)
    assert.equals(1, #received_payload)
    assert.equals("intent-0002", received_payload[1].id)
  end)

  it("payload size scales with intents not raw keystroke count", function()
    local events = {}
    for i = 1, 20 do
      table.insert(events, { t = i * 10, kind = "key", buf = 1, data = { keys = string.rep("x", 2000) } })
      table.insert(events, { t = i * 10 + 1, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = 1, blob = "z" } })
      table.insert(events, { t = i * 10 + 2, kind = "mode", buf = 1, data = { from = "i", to = "n" } })
    end
    write_events(events)
    local got
    agent.set_implementation(function(payload)
      got = payload
      return {}
    end)
    caddie.review()
    assert.equals(20, #got)
    for _, intent in ipairs(got) do
      assert.is_true(#intent.keys <= 600, "intent keys should be capped, got " .. #intent.keys)
    end
  end)

  it("dedupes suggestions with identical suggested_keys and explanation", function()
    write_events({
      { t = 0, kind = "key", buf = 1, data = { keys = "jjjjjj" } },
      { t = 1, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = 1, blob = "x" } },
      { t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } },
    })
    agent.set_implementation(function()
      return {
        { intent_id = "intent-0001", severity = "low",
          current_keys = "jjjjjj", suggested_keys = "5j",
          explanation = "Use a count." },
        { intent_id = "intent-0001", severity = "low",
          current_keys = "jjjjjj", suggested_keys = "5j",
          explanation = "Use a count." },
      }
    end)
    local suggestions = caddie.review()
    local count_5j = 0
    for _, s in ipairs(suggestions) do
      if s.suggested_keys == "5j" and s.explanation == "Use a count." then
        count_5j = count_5j + 1
      end
    end
    assert.equals(1, count_5j)
  end)

  it("attaches a numbered excerpt from the session blob to suggestions", function()
    store.start_session(tmpdir, {})
    local hash = store.write_blob("local a = 1\nlocal b = 2")
    store.write_event({ t = 0, kind = "key", buf = 1, data = { keys = "jjjjj" } })
    store.write_event({ t = 1, kind = "edit", buf = 1, data = { first = 4, last = 4, new_last = 6, blob = hash } })
    store.write_event({ t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } })
    store.stop_session()
    agent.set_implementation(function() return {} end)
    local suggestions = caddie.review({ skip_ui = true })
    local with_excerpt
    for _, s in ipairs(suggestions) do
      if s.excerpt then
        with_excerpt = s
      end
    end
    assert.is_not_nil(with_excerpt)
    assert.equals("5| local a = 1", with_excerpt.excerpt[1])
    assert.equals("6| local b = 2", with_excerpt.excerpt[2])
  end)

  it("notifies that the agent review is running before it completes", function()
    write_events({
      { t = 0, kind = "key", buf = 1, data = { keys = "jjjjj" } },
      { t = 1, kind = "edit", buf = 1, data = { first = 4, last = 4, new_last = 4, blob = "x" } },
      { t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } },
    })
    agent.set_implementation(function(_, _, cb)
      vim.defer_fn(function() cb({}) end, 10)
    end)
    local messages = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, ...)
      table.insert(messages, msg)
    end
    caddie.review({ skip_ui = true })
    vim.notify = orig_notify
    local notified = false
    for _, m in ipairs(messages) do
      if m:lower():find("review", 1, true) then
        notified = true
      end
    end
    assert.is_true(notified)
  end)

  it("returns nil and finishes later when the agent impl is async", function()
    local session = write_events({
      { t = 0, kind = "key", buf = 1, data = { keys = "jjjjj" } },
      { t = 1, kind = "edit", buf = 1, data = { first = 4, last = 4, new_last = 4, blob = "x" } },
      { t = 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } },
    })
    agent.set_implementation(function(_, _, cb)
      vim.defer_fn(function()
        cb({
          { intent_id = "intent-0001", severity = "low",
            current_keys = "jjjjj", suggested_keys = "5j",
            explanation = "Use a count." },
        })
      end, 10)
    end)
    local suggestions = caddie.review({ skip_ui = true })
    assert.is_nil(suggestions)
    local done = vim.wait(2000, function()
      return vim.fn.filereadable(session.review_path) == 1
    end)
    assert.is_true(done)
    local f = io.open(session.review_path, "r")
    local written = vim.fn.json_decode(f:read("*a"))
    f:close()
    local found = false
    for _, s in ipairs(written) do
      if s.suggested_keys == "5j" then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("completes within 10 seconds for <200 intents with mocked agent", function()
    local events = {}
    for i = 1, 150 do
      table.insert(events, { t = i * 10, kind = "key", buf = 1, data = { keys = "jjjjj" } })
      table.insert(events, { t = i * 10 + 1, kind = "edit", buf = 1, data = { first = i, last = i, new_last = i, blob = "z" } })
      table.insert(events, { t = i * 10 + 2, kind = "mode", buf = 1, data = { from = "n", to = "n" } })
    end
    write_events(events)
    agent.set_implementation(function() return {} end)
    local start = vim.uv.hrtime()
    caddie.review()
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    assert.is_true(elapsed_ms < 10000, "review took " .. elapsed_ms .. "ms")
  end)
end)
