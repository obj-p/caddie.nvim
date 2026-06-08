describe("caddie", function()
  before_each(function()
    package.loaded["caddie"] = nil
    package.loaded["caddie.config"] = nil
  end)

  it("loads and applies defaults", function()
    require("caddie").setup()
    local config = require("caddie.config")
    assert.is_true(config.current.autostart)
    assert.equals("anthropic", config.current.agent.provider)
  end)

  it("merges user opts over defaults", function()
    require("caddie").setup({
      autostart = false,
      agent = { model = "claude-haiku-4-5" },
    })
    local config = require("caddie.config")
    assert.is_false(config.current.autostart)
    assert.equals("claude-haiku-4-5", config.current.agent.model)
    assert.equals("anthropic", config.current.agent.provider)
  end)

  it("registers user commands", function()
    vim.cmd("runtime plugin/caddie.lua")
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands.CaddieStart)
    assert.is_not_nil(commands.CaddieStop)
    assert.is_not_nil(commands.CaddieReview)
    assert.is_not_nil(commands.CaddieReplay)
    assert.is_not_nil(commands.CaddieToggleAnnotations)
  end)
end)
