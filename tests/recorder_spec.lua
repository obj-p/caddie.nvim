local function read_events(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then
    return out
  end
  for line in f:lines() do
    table.insert(out, vim.fn.json_decode(line))
  end
  f:close()
  return out
end

local function kinds(events)
  local seen = {}
  for _, e in ipairs(events) do
    seen[e.kind] = (seen[e.kind] or 0) + 1
  end
  return seen
end

describe("recorder", function()
  local recorder, store, tmpdir

  before_each(function()
    package.loaded["caddie"] = nil
    package.loaded["caddie.config"] = nil
    package.loaded["caddie.store"] = nil
    package.loaded["caddie.recorder"] = nil
    tmpdir = vim.fn.tempname()
    require("caddie").setup({ data_dir = tmpdir, autostart = false })
    recorder = require("caddie.recorder")
    store = require("caddie.store")
  end)

  after_each(function()
    recorder.stop()
  end)

  it("notifies when recording starts and stops", function()
    local msgs = {}
    local orig = vim.notify
    vim.notify = function(m)
      table.insert(msgs, m)
    end
    recorder.start()
    recorder.stop()
    vim.notify = orig
    local started, stopped = false, false
    for _, m in ipairs(msgs) do
      if m:lower():find("start", 1, true) then
        started = true
      end
      if m:lower():find("stop", 1, true) then
        stopped = true
      end
    end
    assert.is_true(started, "expected a start notification")
    assert.is_true(stopped, "expected a stop notification")
  end)

  it("creates a session dir on start", function()
    recorder.start()
    assert.is_not_nil(store.active)
    assert.equals(1, vim.fn.isdirectory(store.active.dir))
    assert.equals(1, vim.fn.isdirectory(store.active.blobs_dir))
  end)

  it("captures events of all 5 kinds", function()
    recorder.start()
    local session = store.active

    local buf = vim.api.nvim_create_buf(true, false)
    local file = tmpdir .. "/sample.txt"
    vim.api.nvim_buf_set_name(buf, file)
    vim.api.nvim_set_current_buf(buf)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })

    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "tx", false)
    end
    feed("ix<Esc>")
    feed(":echo 'hi'<CR>")

    vim.api.nvim_buf_call(buf, function() vim.cmd("write!") end)

    recorder.stop()
    local events = read_events(session.events_path)
    local seen = kinds(events)

    assert.is_true((seen.key or 0) > 0, "expected key events")
    assert.is_true((seen.mode or 0) > 0, "expected mode events")
    assert.is_true((seen.edit or 0) > 0, "expected edit events")
    assert.is_true((seen.write or 0) > 0, "expected write events")
    assert.is_true((seen.cmd or 0) > 0, "expected cmd events")
  end)

  it("records the file path on edit events", function()
    recorder.start()
    local session = store.active

    local buf = vim.api.nvim_create_buf(true, false)
    local file = tmpdir .. "/sample.txt"
    vim.api.nvim_buf_set_name(buf, file)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })

    recorder.stop()
    local events = read_events(session.events_path)
    local saw = false
    for _, e in ipairs(events) do
      if e.kind == "edit" and e.data.path and vim.endswith(e.data.path, "/sample.txt") then
        saw = true
      end
    end
    assert.is_true(saw, "expected edit events to carry the file path")
  end)

  it("redacts .env files: no blob written, blob field is null", function()
    recorder.start()
    local session = store.active

    local buf = vim.api.nvim_create_buf(true, false)
    local file = tmpdir .. "/.env"
    vim.api.nvim_buf_set_name(buf, file)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SECRET=topsecret" })
    vim.api.nvim_buf_call(buf, function() vim.cmd("write!") end)

    recorder.stop()
    local events = read_events(session.events_path)
    local saw_redacted_edit = false
    local saw_redacted_write = false
    for _, e in ipairs(events) do
      if e.kind == "edit" and e.data.blob == vim.NIL then
        saw_redacted_edit = true
      end
      if e.kind == "write" and e.data.blob == vim.NIL and vim.endswith(e.data.path, "/.env") then
        saw_redacted_write = true
      end
    end
    assert.is_true(saw_redacted_edit, "expected redacted edit event with null blob")
    assert.is_true(saw_redacted_write, "expected redacted write event with null blob")

    local blob_files = vim.fn.readdir(session.blobs_dir)
    assert.equals(0, #blob_files, "expected no blob files for redacted session")
  end)

  it("does not record keystrokes typed in a redacted file", function()
    recorder.start()
    local session = store.active

    local buf = vim.api.nvim_create_buf(true, false)
    local file = tmpdir .. "/.env"
    vim.api.nvim_buf_set_name(buf, file)
    vim.api.nvim_set_current_buf(buf)

    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "tx", false)
    end
    feed("iSECRET=topsecret<Esc>")

    recorder.stop()
    local events = read_events(session.events_path)
    for _, e in ipairs(events) do
      assert.is_not.equal("key", e.kind, "no key events should be recorded in a redacted buffer")
    end
  end)
end)
