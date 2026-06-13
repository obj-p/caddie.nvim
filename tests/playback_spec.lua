describe("playback", function()
  local playback

  before_each(function()
    package.loaded["caddie.playback"] = nil
    playback = require("caddie.playback")
  end)

  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  it("plays the keys on a seeded buffer and ends in the executed state", function()
    local done_buf
    playback.play({
      lines = { "foo bar baz" },
      line = 1,
      keys = "dw",
      delay = 0,
    }, function(buf)
      done_buf = buf
    end)
    vim.wait(2000, function()
      return done_buf ~= nil
    end)
    assert.is_not_nil(done_buf)
    local lines = vim.api.nvim_buf_get_lines(done_buf, 0, -1, false)
    assert.equals("bar baz", lines[1])
  end)

  it("shows the fed keys in the keycast", function()
    local cast
    playback.play({
      lines = { "L1", "L2", "L3", "L4", "L5", "L6" },
      line = 1,
      keys = "5j",
      delay = 0,
    }, function(_, keycast_text)
      cast = keycast_text
    end)
    vim.wait(2000, function()
      return cast ~= nil
    end)
    assert.is_not_nil(cast)
    assert.is_true(cast:find("5", 1, true) ~= nil)
    assert.is_true(cast:find("j", 1, true) ~= nil)
  end)
end)
