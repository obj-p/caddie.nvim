if vim.g.loaded_caddie then
  return
end
vim.g.loaded_caddie = 1

vim.api.nvim_create_user_command("CaddieStart", function()
  require("caddie.recorder").start()
end, {})
vim.api.nvim_create_user_command("CaddieStop", function()
  require("caddie.recorder").stop()
end, {})
vim.api.nvim_create_user_command("CaddieReview", function(args)
  local n = tonumber(args.args)
  require("caddie").review({ last_n_min = n })
end, { nargs = "?" })
vim.api.nvim_create_user_command("CaddieReplay", function()
  require("caddie.replay").pick()
end, {})
vim.api.nvim_create_user_command("CaddieToggleAnnotations", function()
  require("caddie.annotations").toggle()
end, {})
