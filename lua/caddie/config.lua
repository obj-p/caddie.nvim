local M = {}

M.defaults = {
  data_dir = vim.fn.stdpath("data") .. "/caddie",
  autostart = false,
  auto_review_on_exit = false,
  annotations_enabled = true,
  redact_globs = { ".env", ".env.*", "*.pem", "*.key" },
  agent = {
    provider = "anthropic",
    model = "claude-opus-4-7",
    api_key_env = "ANTHROPIC_API_KEY",
  },
}

M.current = vim.deepcopy(M.defaults)

function M.apply(opts)
  M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
