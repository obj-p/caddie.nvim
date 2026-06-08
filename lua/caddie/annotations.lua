local M = {}

M._ns = vim.api.nvim_create_namespace("caddie_annotations")
M._sign_group = "caddie_annotations"
M._suggestions = {}
M._visible = true
M._signs_defined = false

local function ensure_setup()
  if M._signs_defined then
    return
  end
  pcall(vim.api.nvim_set_hl, 0, "CaddieHint", { fg = "#888888", italic = true, default = true })
  pcall(vim.fn.sign_define, "CaddieLow", { text = "·", texthl = "DiagnosticHint" })
  pcall(vim.fn.sign_define, "CaddieMedium", { text = "▸", texthl = "DiagnosticWarn" })
  pcall(vim.fn.sign_define, "CaddieHigh", { text = "▶", texthl = "DiagnosticError" })
  M._signs_defined = true
end

local function find_buf(path)
  if not path or path == "" then
    return nil
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == path then
      return b
    end
  end
end

local function clear_all()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      pcall(vim.api.nvim_buf_clear_namespace, b, M._ns, 0, -1)
      pcall(vim.fn.sign_unplace, M._sign_group, { buffer = b })
    end
  end
end

local function sign_for(severity)
  if severity == "low" then
    return "CaddieLow"
  elseif severity == "high" then
    return "CaddieHigh"
  end
  return "CaddieMedium"
end

local function apply()
  ensure_setup()
  clear_all()
  if not M._visible then
    return
  end
  for _, s in ipairs(M._suggestions) do
    local lr = s.line_range
    if s.path and lr and lr ~= vim.NIL and type(lr) == "table" then
      local buf = find_buf(s.path)
      if buf and vim.api.nvim_buf_is_valid(buf) then
        local row = math.max(0, lr[1] or 0)
        local line_count = vim.api.nvim_buf_line_count(buf)
        if row >= line_count then
          row = line_count - 1
        end
        pcall(vim.api.nvim_buf_set_extmark, buf, M._ns, row, 0, {
          virt_text = { { " → " .. (s.suggested_keys or ""), "CaddieHint" } },
          virt_text_pos = "eol",
        })
        pcall(vim.fn.sign_place, 0, M._sign_group, sign_for(s.severity), buf, { lnum = row + 1 })
      end
    end
  end
end

function M.refresh(suggestions)
  M._suggestions = suggestions or {}
  M._visible = true
  apply()
end

function M.toggle()
  M._visible = not M._visible
  apply()
  return M._visible
end

function M.is_visible()
  return M._visible
end

function M.namespace()
  return M._ns
end

return M
