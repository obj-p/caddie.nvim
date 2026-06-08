local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return vim.fn.json_decode(s)
end

describe("store", function()
  local store, tmpdir

  before_each(function()
    package.loaded["caddie.store"] = nil
    store = require("caddie.store")
    tmpdir = vim.fn.tempname()
  end)

  after_each(function()
    store.stop_session()
  end)

  it("writes meta.json with start time, nvim version, cwd on start", function()
    local session = store.start_session(tmpdir, {})
    local meta = read_json(session.meta_path)
    assert.is_not_nil(meta)
    assert.is_string(meta.start_time)
    assert.is_string(meta.nvim_version)
    assert.is_string(meta.cwd)
    assert.equals(session.id, meta.id)
    assert.is_nil(meta.end_time)
  end)

  it("updates meta.json with end_time on stop", function()
    local session = store.start_session(tmpdir, {})
    local meta_path = session.meta_path
    store.stop_session()
    local meta = read_json(meta_path)
    assert.is_string(meta.end_time)
  end)

  it("session ids sort chronologically", function()
    local s1 = store.start_session(tmpdir, {})
    local id1 = s1.id
    store.stop_session()
    vim.uv.sleep(1100)
    local s2 = store.start_session(tmpdir, {})
    local id2 = s2.id
    store.stop_session()
    assert.is_true(id1 < id2, id1 .. " should sort before " .. id2)
  end)

  it("dedupes blobs across sessions under the same data_dir", function()
    local s1 = store.start_session(tmpdir, {})
    local hash1 = store.write_blob("identical content")
    store.stop_session()

    local s2 = store.start_session(tmpdir, {})
    local hash2 = store.write_blob("identical content")
    store.stop_session()

    assert.equals(hash1, hash2)
    assert.equals(s1.blobs_dir, s2.blobs_dir)
    local files = vim.fn.readdir(s1.blobs_dir)
    assert.equals(1, #files)
  end)

  it("events.jsonl is newline-terminated and parseable after a flush", function()
    local session = store.start_session(tmpdir, {})
    store.write_event({ t = 0, kind = "key", buf = 1, data = { keys = "a" } })
    store.write_event({ t = 1, kind = "key", buf = 1, data = { keys = "b" } })

    local f = io.open(session.events_path, "r")
    local content = f:read("*a")
    f:close()

    assert.equals("\n", content:sub(-1))

    local lines = vim.split(content, "\n", { trimempty = true })
    assert.equals(2, #lines)
    for _, line in ipairs(lines) do
      local ok, decoded = pcall(vim.fn.json_decode, line)
      assert.is_true(ok)
      assert.equals("key", decoded.kind)
    end
  end)
end)
