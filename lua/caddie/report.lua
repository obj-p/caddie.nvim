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

function M.render(suggestions)
  suggestions = sort_suggestions(vim.deepcopy(suggestions or {}))
  local lines = { "# Caddie Review", "", string.format("%d suggestions", #suggestions), "" }
  for _, s in ipairs(suggestions) do
    table.insert(lines, "## [" .. (s.severity or "?") .. "] " .. (s.intent_id or ""))
    table.insert(lines, "")
    table.insert(lines, "- Current: `" .. (s.current_keys or "") .. "`")
    table.insert(lines, "- Suggested: `" .. (s.suggested_keys or "") .. "`")
    table.insert(lines, "- " .. (s.explanation or ""))
    local lr = s.line_range
    if s.path and lr and lr ~= vim.NIL and type(lr) == "table" then
      table.insert(lines, "- " .. s.path .. ":" .. ((lr[1] or 0) + 1))
    end
    table.insert(lines, "")
  end
  return lines
end

function M.open(suggestions)
  local lines = M.render(suggestions)
  vim.cmd("botright vsplit")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  return buf
end

return M
