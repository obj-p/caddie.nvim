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
