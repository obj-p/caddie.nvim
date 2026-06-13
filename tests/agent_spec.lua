describe("agent claude-code provider", function()
  local agent

  before_each(function()
    package.loaded["caddie.agent"] = nil
    agent = require("caddie.agent")
  end)

  it("build_claude_prompt includes system rubric and JSON payload", function()
    local prompt = agent._build_claude_prompt({ { id = "intent-0001", keys = "jjjj" } })
    assert.is_true(prompt:find("Vim coach", 1, true) ~= nil)
    assert.is_true(prompt:find("intent-0001", 1, true) ~= nil)
  end)

  it("build_claude_prompt asks for a title describing the user's activity", function()
    local prompt = agent._build_claude_prompt({ { id = "intent-0001", keys = "jjjj" } })
    assert.is_true(prompt:find("title", 1, true) ~= nil)
  end)

  it("build_claude_prompt tells the agent to use null over a vague title", function()
    local prompt = agent._build_claude_prompt({ { id = "intent-0001", keys = "jjjj" } })
    assert.is_true(prompt:find("title (string or null", 1, true) ~= nil)
    assert.is_true(prompt:lower():find("vague", 1, true) ~= nil)
  end)

  it("parse_claude_response unwraps the result field and parses JSON", function()
    local fake_stdout = vim.fn.json_encode({
      type = "result",
      subtype = "success",
      is_error = false,
      result = vim.fn.json_encode({
        {
          intent_id = "intent-0001",
          severity = "medium",
          current_keys = "jjjj",
          suggested_keys = "5j",
          explanation = "use count",
        },
      }),
    })
    local suggestions, err = agent._parse_claude_response(fake_stdout)
    assert.is_nil(err)
    assert.equals(1, #suggestions)
    assert.equals("5j", suggestions[1].suggested_keys)
  end)

  it("parse_claude_response returns error for invalid wrapper", function()
    local suggestions, err = agent._parse_claude_response("not json")
    assert.is_nil(suggestions)
    assert.is_string(err)
  end)

  it("parse_claude_response strips ```json fences from the result", function()
    local payload = vim.fn.json_encode({
      {
        intent_id = "intent-0001",
        severity = "high",
        current_keys = "jjjj",
        suggested_keys = "4j",
        explanation = "use a count",
      },
    })
    local fake_stdout = vim.fn.json_encode({
      type = "result",
      result = "```json\n" .. payload .. "\n```",
    })
    local suggestions, err = agent._parse_claude_response(fake_stdout)
    assert.is_nil(err)
    assert.equals(1, #suggestions)
    assert.equals("4j", suggestions[1].suggested_keys)
  end)
end)
