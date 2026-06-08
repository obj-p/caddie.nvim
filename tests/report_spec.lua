describe("report", function()
  local report

  before_each(function()
    package.loaded["caddie.report"] = nil
    report = require("caddie.report")
  end)

  it("sorts by severity then intent_id", function()
    local lines = report.render({
      { intent_id = "intent-0003", severity = "low", current_keys = "a", suggested_keys = "b", explanation = "c" },
      { intent_id = "intent-0001", severity = "high", current_keys = "a", suggested_keys = "b", explanation = "c" },
      { intent_id = "intent-0002", severity = "medium", current_keys = "a", suggested_keys = "b", explanation = "c" },
    })
    local order = {}
    for _, l in ipairs(lines) do
      local id = l:match("intent%-(%d+)")
      if id then
        table.insert(order, id)
      end
    end
    assert.same({ "0001", "0002", "0003" }, order)
  end)

  it("renders all suggestions without truncation for 100+ items", function()
    local big = {}
    for i = 1, 120 do
      table.insert(big, {
        intent_id = string.format("intent-%04d", i),
        severity = "low",
        current_keys = "x", suggested_keys = "y", explanation = "z",
      })
    end
    local lines = report.render(big)
    local count = 0
    for _, l in ipairs(lines) do
      if l:match("^## %[low%] intent%-") then
        count = count + 1
      end
    end
    assert.equals(120, count)
  end)

  it("open creates a scratch markdown buffer", function()
    local buf = report.open({
      { intent_id = "intent-0001", severity = "high",
        current_keys = "a", suggested_keys = "b", explanation = "c" },
    })
    assert.equals("nofile", vim.api.nvim_get_option_value("buftype", { buf = buf }))
    assert.equals("markdown", vim.api.nvim_get_option_value("filetype", { buf = buf }))
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("# Caddie Review", lines[1])
  end)
end)
