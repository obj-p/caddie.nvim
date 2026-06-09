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

    it("hard-splits on cmd events", function()
      local events = {
        { t = 0, kind = "key", buf = 1, data = { keys = "j" } },
        { t = 1, kind = "cmd", buf = 1, data = { type = "ex", text = "write" } },
        { t = 2, kind = "key", buf = 1, data = { keys = "k" } },
        { t = 3, kind = "cmd", buf = 1, data = { type = "ex", text = "e foo.txt" } },
        { t = 4, kind = "key", buf = 1, data = { keys = "h" } },
      }
      local intents = rules.segment(events)
      assert.equals(3, #intents)
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

    it("does not fire on Insert-mode text containing j or h or k or l", function()
      local intent = {
        id = "intent-0001",
        events = {
          { t = 0, kind = "mode", buf = 1, data = { from = "n", to = "i" } },
          { t = 1, kind = "key", buf = 1, data = { keys = "h" } },
          { t = 2, kind = "key", buf = 1, data = { keys = "e" } },
          { t = 3, kind = "key", buf = 1, data = { keys = "l" } },
          { t = 4, kind = "key", buf = 1, data = { keys = "l" } },
          { t = 5, kind = "key", buf = 1, data = { keys = "o" } },
          { t = 6, kind = "key", buf = 1, data = { keys = "<Esc>" } },
          { t = 7, kind = "mode", buf = 1, data = { from = "i", to = "n" } },
        },
      }
      local metrics = rules.analyze(intent)
      local suggestions = rules.run_rules(intent, metrics)
      for _, s in ipairs(suggestions) do
        assert.is_nil(s.explanation:match("hjkl"), "should not fire for 'hello' in Insert")
      end
    end)
  end)

  describe("dd-then-p rule", function()
    it("does not fire on Insert-mode text containing 'dd' and 'p'", function()
      local intent = {
        id = "intent-0001",
        events = {
          { t = 0, kind = "mode", buf = 1, data = { from = "n", to = "i" } },
          { t = 1, kind = "key", buf = 1, data = { keys = "c" } },
          { t = 2, kind = "key", buf = 1, data = { keys = "a" } },
          { t = 3, kind = "key", buf = 1, data = { keys = "d" } },
          { t = 4, kind = "key", buf = 1, data = { keys = "d" } },
          { t = 5, kind = "key", buf = 1, data = { keys = "i" } },
          { t = 6, kind = "key", buf = 1, data = { keys = "e" } },
          { t = 7, kind = "key", buf = 1, data = { keys = "<Esc>" } },
          { t = 8, kind = "mode", buf = 1, data = { from = "i", to = "n" } },
          { t = 9, kind = "key", buf = 1, data = { keys = "p" } },
        },
      }
      local metrics = rules.analyze(intent)
      for _, s in ipairs(rules.run_rules(intent, metrics)) do
        assert.is_nil(s.explanation:match("dd...p"), "should not fire for typed 'caddie' + p")
      end
    end)

    it("fires on real Normal-mode dd then navigate then p", function()
      local intent = {
        id = "intent-0001",
        events = {
          { t = 0, kind = "key", buf = 1, data = { keys = "d" } },
          { t = 1, kind = "key", buf = 1, data = { keys = "d" } },
          { t = 2, kind = "key", buf = 1, data = { keys = "j" } },
          { t = 3, kind = "key", buf = 1, data = { keys = "p" } },
        },
      }
      local metrics = rules.analyze(intent)
      local found
      for _, s in ipairs(rules.run_rules(intent, metrics)) do
        if s.explanation:match("dd") then found = s end
      end
      assert.is_not_nil(found)
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
