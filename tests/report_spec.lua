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

  it("headers use the title, then path and line, then intent_id", function()
    local lines = report.render({
      { intent_id = "intent-0001", severity = "high", title = "Scrolling through a long function",
        current_keys = "a", suggested_keys = "b", explanation = "c" },
      { intent_id = "intent-0002", severity = "medium", title = vim.NIL,
        current_keys = "a", suggested_keys = "b", explanation = "c",
        path = "/tmp/foo.lua", line_range = { 9, 9 } },
      { intent_id = "intent-0003", severity = "low",
        current_keys = "a", suggested_keys = "b", explanation = "c" },
    })
    local headers = {}
    for _, l in ipairs(lines) do
      if l:match("^## ") then
        table.insert(headers, l)
      end
    end
    assert.equals("## [high] Scrolling through a long function", headers[1])
    assert.equals("## [medium] foo.lua:10", headers[2])
    assert.equals("## [low] intent-0003", headers[3])
  end)

  it("renders the excerpt as a fenced code block", function()
    local lines = report.render({
      { intent_id = "intent-0001", severity = "low",
        current_keys = "a", suggested_keys = "b", explanation = "c",
        excerpt = { "5| local a = 1", "6| local b = 2" } },
    })
    local fence_at
    for i, l in ipairs(lines) do
      if l == "```" and not fence_at then
        fence_at = i
      end
    end
    assert.is_not_nil(fence_at)
    assert.equals("5| local a = 1", lines[fence_at + 1])
    assert.equals("6| local b = 2", lines[fence_at + 2])
    assert.equals("```", lines[fence_at + 3])
  end)

  it("marks jump and play availability", function()
    local lines = report.render({
      { intent_id = "intent-0001", severity = "medium", current_keys = "xxxx",
        suggested_keys = "dw", suggested_exec = "dw", explanation = "e",
        path = "/tmp/foo.lua", line_range = { 4, 4 },
        excerpt = { "5| foo bar" } },
    })
    local joined = table.concat(lines, "\n")
    assert.is_true(joined:find("jump", 1, true) ~= nil)
    assert.is_true(joined:find("play", 1, true) ~= nil)
  end)

  it("omits action markers when nothing is available", function()
    local lines = report.render({
      { intent_id = "intent-0001", severity = "low", current_keys = "a",
        suggested_keys = "b", explanation = "c" },
    })
    local joined = table.concat(lines, "\n")
    assert.is_nil(joined:find("jump", 1, true))
    assert.is_nil(joined:find("play", 1, true))
  end)

  it("exposes play data for suggestions with an exec and excerpt", function()
    local _, _, plays = report.render({
      { intent_id = "intent-0001", severity = "medium", current_keys = "jjjjj",
        suggested_keys = "w", suggested_exec = "w", explanation = "e",
        path = "/tmp/foo.lua", line_range = { 4, 4 },
        excerpt = { "5| local a = 1", "6| local b = 2" } },
    })
    local pd
    for _, p in pairs(plays) do
      if p then
        pd = p
      end
    end
    assert.is_not_nil(pd)
    assert.equals("w", pd.keys)
    assert.equals(1, pd.line)
    assert.same({ "local a = 1", "local b = 2" }, pd.lines)
  end)

  it("maps p to replay the suggestion under the cursor", function()
    local captured
    package.loaded["caddie.playback"] = { play = function(o)
      captured = o
    end }
    local buf = report.open({
      { intent_id = "intent-0001", severity = "medium", current_keys = "jjjjj",
        suggested_keys = "w", suggested_exec = "w", explanation = "e",
        path = "/tmp/foo.lua", line_range = { 4, 4 },
        excerpt = { "5| local a = 1", "6| local b = 2" } },
    })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local lnum
    for i, l in ipairs(lines) do
      if l:find("Suggested", 1, true) then
        lnum = i
      end
    end
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    local cb
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if m.lhs == "p" then
        cb = m.callback
      end
    end
    assert.is_not_nil(cb)
    cb()
    assert.is_not_nil(captured)
    assert.equals("w", captured.keys)
    package.loaded["caddie.playback"] = nil
  end)

  it("open maps <CR> to jump to the suggestion location", function()
    local target = vim.fn.tempname()
    vim.fn.writefile({ "one", "two", "three", "four", "five" }, target)
    local buf = report.open({
      { intent_id = "intent-0001", severity = "high",
        current_keys = "jjjj", suggested_keys = "4j", explanation = "use count",
        path = target, line_range = { 3, 3 } },
    })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local lnum
    for i, l in ipairs(lines) do
      if l:find("Current:", 1, true) then
        lnum = i
      end
    end
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    local cb
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if m.lhs == "<CR>" then
        cb = m.callback
      end
    end
    assert.is_not_nil(cb)
    cb()
    assert.equals(vim.uv.fs_realpath(target), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
    assert.equals(4, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("open maps q to close the report window", function()
    local wins_before = #vim.api.nvim_list_wins()
    local buf = report.open({
      { intent_id = "intent-0001", severity = "high",
        current_keys = "a", suggested_keys = "b", explanation = "c" },
    })
    local has_q = false
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if m.lhs == "q" then
        has_q = true
      end
    end
    assert.is_true(has_q)
    vim.cmd("close")
    assert.equals(wins_before, #vim.api.nvim_list_wins())
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
