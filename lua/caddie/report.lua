local M = {}

local SEVERITY_RANK = { high = 0, medium = 1, low = 2 }

local function sort_suggestions(list)
  table.sort(list, function(a, b)
    local ra = SEVERITY_RANK[a.severity] or 99
    local rb = SEVERITY_RANK[b.severity] or 99
    if ra ~= rb then
      return ra < rb
    end
    return (a.intent_id or "") < (b.intent_id or "")
  end)
  return list
end

local function play_data(s)
  if not s.suggested_exec or s.suggested_exec == vim.NIL or s.suggested_exec == "" then
    return nil
  end
  if type(s.excerpt) ~= "table" or #s.excerpt == 0 then
    return nil
  end
  local raw = {}
  for _, el in ipairs(s.excerpt) do
    table.insert(raw, (el:gsub("^%d+| ?", "")))
  end
  local target = 1
  if type(s.line_range) == "table" then
    local want = (s.line_range[1] or 0) + 1
    for idx, el in ipairs(s.excerpt) do
      if tonumber(el:match("^(%d+)|")) == want then
        target = idx
        break
      end
    end
  end
  return { lines = raw, line = target, keys = s.suggested_exec }
end

function M.render(suggestions)
  suggestions = sort_suggestions(vim.deepcopy(suggestions or {}))
  local lines = { "# Caddie Review", "", string.format("%d suggestions", #suggestions), "" }
  local targets = {}
  local plays = {}
  for _, s in ipairs(suggestions) do
    local lr = s.line_range
    local has_location = s.path and lr and lr ~= vim.NIL and type(lr) == "table"
    local header = s.title
    if not header or header == vim.NIL or header == "" then
      if has_location then
        header = vim.fn.fnamemodify(s.path, ":t") .. ":" .. ((lr[1] or 0) + 1)
      else
        header = s.intent_id or ""
      end
    end
    local first = #lines + 1
    table.insert(lines, "## [" .. (s.severity or "?") .. "] " .. header)
    table.insert(lines, "")
    table.insert(lines, "- Current: `" .. (s.current_keys or "") .. "`")
    table.insert(lines, "- Suggested: `" .. (s.suggested_keys or "") .. "`")
    table.insert(lines, "- " .. (s.explanation or ""))
    if has_location then
      table.insert(lines, "- " .. s.path .. ":" .. ((lr[1] or 0) + 1))
    end
    if type(s.excerpt) == "table" and #s.excerpt > 0 then
      table.insert(lines, "")
      table.insert(lines, "```")
      for _, el in ipairs(s.excerpt) do
        table.insert(lines, el)
      end
      table.insert(lines, "```")
    end
    local pd = play_data(s)
    for i = first, #lines do
      if has_location then
        targets[i] = { path = s.path, line = (lr[1] or 0) + 1 }
      end
      if pd then
        plays[i] = pd
      end
    end
    table.insert(lines, "")
  end
  return lines, targets, plays
end

function M.open(suggestions)
  local lines, targets, plays = M.render(suggestions)
  vim.cmd("botright vsplit")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.keymap.set("n", "<CR>", function()
    local t = targets[vim.api.nvim_win_get_cursor(0)[1]]
    if not t then
      return
    end
    vim.cmd("wincmd p")
    vim.cmd.edit(vim.fn.fnameescape(t.path))
    local line = math.min(t.line, vim.api.nvim_buf_line_count(0))
    vim.api.nvim_win_set_cursor(0, { line, 0 })
  end, { buffer = buf })
  vim.keymap.set("n", "p", function()
    local pd = plays[vim.api.nvim_win_get_cursor(0)[1]]
    if not pd then
      vim.notify("caddie: nothing to replay here", vim.log.levels.INFO)
      return
    end
    require("caddie.playback").play({ lines = pd.lines, line = pd.line, keys = pd.keys })
  end, { buffer = buf })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
  return buf
end

return M
