describe("replay", function()
  local replay, store, caddie, tmpdir

  before_each(function()
    package.loaded["caddie"] = nil
    package.loaded["caddie.config"] = nil
    package.loaded["caddie.store"] = nil
    package.loaded["caddie.replay"] = nil
    tmpdir = vim.fn.tempname()
    caddie = require("caddie")
    caddie.setup({ data_dir = tmpdir, autostart = false })
    store = require("caddie.store")
    replay = require("caddie.replay")
  end)

  local function make_session_with_edits(lines_a, lines_b)
    local session = store.start_session(tmpdir, {})
    local blob_a = store.write_blob(table.concat(lines_a, "\n"))
    local blob_b = store.write_blob(table.concat(lines_b, "\n"))
    store.write_event({ t = 0, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = #lines_a, blob = blob_a } })
    store.write_event({ t = 1, kind = "edit", buf = 1, data = { first = 0, last = #lines_a, new_last = #lines_b, blob = blob_b } })
    store.stop_session()
    return session
  end

  it("lists sessions excluding the shared blobs dir", function()
    make_session_with_edits({ "x" }, { "y" })
    make_session_with_edits({ "a" }, { "b" })
    local sessions = replay.list_sessions()
    assert.equals(2, #sessions)
    for _, s in ipairs(sessions) do
      assert.is_not.equal("blobs", s.id)
    end
  end)

  it("reconstructs final buffer state within 1-line delta", function()
    local target = { "hello", "world", "again" }
    local session = make_session_with_edits({ "first" }, target)
    replay.start(session.dir)
    replay.goto_index(replay.event_count())
    local replay_buf = vim.api.nvim_get_current_buf()
    local got = vim.api.nvim_buf_get_lines(replay_buf, 0, -1, false)
    assert.is_true(math.abs(#got - #target) <= 1)
    for i = 1, math.min(#got, #target) do
      assert.equals(target[i], got[i])
    end
  end)

  it("step navigates forward and back", function()
    local session = make_session_with_edits({ "a" }, { "b" })
    replay.start(session.dir)
    assert.equals(0, replay.current_index())
    replay.step(1)
    assert.equals(1, replay.current_index())
    replay.step(1)
    assert.equals(2, replay.current_index())
    replay.step(-1)
    assert.equals(1, replay.current_index())
  end)
end)
