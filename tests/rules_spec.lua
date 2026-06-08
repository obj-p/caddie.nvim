describe("rules", function()
  local rules

  before_each(function()
    package.loaded["caddie.rules"] = nil
    rules = require("caddie.rules")
  end)

  describe("segment", function()
    it("splits on Normal-mode entry after an edit", function()
      local events = {
        { t = 0, kind = "key", buf = 1, data = { keys = "i" } },
        { t = 1, kind = "mode", buf = 1, data = { from = "n", to = "i" } },
        { t = 2, kind = "key", buf = 1, data = { keys = "a" } },
        { t = 3, kind = "edit", buf = 1, data = { first = 0, last = 0, new_last = 1, blob = "x" } },
        { t = 4, kind = "key", buf = 1, data = { keys = "<Esc>" } },
        { t = 5, kind = "mode", buf = 1, data = { from = "i", to = "n" } },
        { t = 6, kind = "key", buf = 1, data = { keys = "j" } },
        { t = 7, kind = "edit", buf = 1, data = { first = 1, last = 1, new_last = 2, blob = "y" } },
        { t = 8, kind = "mode", buf = 1, data = { from = "n", to = "n" } },
      }
      local intents = rules.segment(events)
      assert.equals(2, #intents)
      assert.equals("intent-0001", intents[1].id)
      assert.equals("intent-0002", intents[2].id)
    end)

    it("hard-splits on write", function()
      local events = {
        { t = 0, kind = "edit", buf = 1, data = { first = 0, last = 1, new_last = 1, blob = "x" } },
        { t = 1, kind = "write", buf = 1, data = { path = "/x", blob = "x" } },
        { t = 2, kind = "key", buf = 1, data = { keys = "j" } },
      }
      local intents = rules.segment(events)
      assert.equals(2, #intents)
    end)
  end)

  describe("hjkl-spam rule", function()
    it("fires on 4+ consecutive hjkl keys", function()
      local intent = {
        id = "intent-0001",
        events = {
          { t = 0, kind = "key", buf = 1, data = { keys = "jjjjj" } },
          { t = 1, kind = "edit", buf = 1, data = { first = 4, last = 4, new_last = 4, blob = "x" } },
        },
      }
      local metrics = rules.analyze(intent)
      local suggestions = rules.run_rules(intent, metrics)
      local found
      for _, s in ipairs(suggestions) do
        if s.explanation:match("hjkl") then
          found = s
        end
      end
      assert.is_not_nil(found)
      assert.equals("medium", found.severity)
      assert.equals("intent-0001", found.intent_id)
    end)

    it("does not fire on short runs", function()
      local intent = {
        id = "intent-0001",
        events = {
          { t = 0, kind = "key", buf = 1, data = { keys = "jj" } },
        },
      }
      local metrics = rules.analyze(intent)
      local suggestions = rules.run_rules(intent, metrics)
      for _, s in ipairs(suggestions) do
        assert.is_nil(s.explanation:match("hjkl"))
      end
    end)
  end)

  describe("redaction", function()
    it("flags intent with vim.NIL blob as redacted", function()
      local intent = {
        events = {
          { t = 0, kind = "edit", buf = 1, data = { first = 0, last = 1, new_last = 1, blob = vim.NIL } },
        },
      }
      assert.is_true(rules.is_redacted_intent(intent))
    end)

    it("does not flag intent with valid blob", function()
      local intent = {
        events = {
          { t = 0, kind = "edit", buf = 1, data = { first = 0, last = 1, new_last = 1, blob = "abc" } },
        },
      }
      assert.is_false(rules.is_redacted_intent(intent))
    end)
  end)
end)
