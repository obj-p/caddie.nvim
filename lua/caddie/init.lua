local M = {}

function M.setup(opts)
  local config = require("caddie.config")
  config.apply(opts)
  if config.current.autostart then
    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = function()
        require("caddie.recorder").start()
      end,
    })
  end
end

return M
