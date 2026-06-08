describe("annotations", function()
  local annotations, buf, path

  before_each(function()
    package.loaded["caddie.annotations"] = nil
    annotations = require("caddie.annotations")
    local raw = vim.fn.tempname() .. ".lua"
    buf = vim.fn.bufadd(raw)
    vim.fn.bufload(buf)
    path = vim.api.nvim_buf_get_name(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2", "line 3" })
  end)

  after_each(function()
    annotations.refresh({})
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  local function marks()
    return vim.api.nvim_buf_get_extmarks(buf, annotations.namespace(), 0, -1, {})
  end

  local function rows()
    local rs = {}
    for _, m in ipairs(marks()) do
      table.insert(rs, m[2])
    end
    return rs
  end

  local function contains(t, v)
    for _, x in ipairs(t) do
      if x == v then
        return true
      end
    end
    return false
  end

  it("places a mark at the suggested line", function()
    annotations.refresh({
      { intent_id = "i1", severity = "medium", suggested_keys = "fX",
        explanation = "x", path = path, line_range = { 1, 1 } },
    })
    assert.is_true(contains(rows(), 1), "expected a mark on row 1")
  end)

  it("survives subsequent buffer edits (line shifts)", function()
    annotations.refresh({
      { intent_id = "i1", severity = "medium", suggested_keys = "fX",
        explanation = "x", path = path, line_range = { 2, 2 } },
    })
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "inserted" })
    assert.is_true(contains(rows(), 3), "expected mark to follow line shift to row 3")
  end)

  it("toggle hides marks and showing restores them at correct lines", function()
    annotations.refresh({
      { intent_id = "i1", severity = "low", suggested_keys = "k",
        explanation = "x", path = path, line_range = { 0, 0 } },
    })
    assert.is_true(contains(rows(), 0))
    annotations.toggle()
    assert.equals(0, #marks())
    assert.is_false(annotations.is_visible())
    annotations.toggle()
    assert.is_true(contains(rows(), 0))
    assert.is_true(annotations.is_visible())
  end)
end)
