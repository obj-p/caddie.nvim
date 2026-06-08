if vim.g.loaded_caddie then
  return
end
vim.g.loaded_caddie = 1

local function stub(name)
  return function()
    vim.notify("caddie: " .. name .. " not yet implemented", vim.log.levels.WARN)
  end
end

vim.api.nvim_create_user_command("CaddieStart", stub("CaddieStart"), {})
vim.api.nvim_create_user_command("CaddieStop", stub("CaddieStop"), {})
vim.api.nvim_create_user_command("CaddieReview", stub("CaddieReview"), { nargs = "?" })
vim.api.nvim_create_user_command("CaddieReplay", stub("CaddieReplay"), {})
vim.api.nvim_create_user_command("CaddieToggleAnnotations", stub("CaddieToggleAnnotations"), {})
