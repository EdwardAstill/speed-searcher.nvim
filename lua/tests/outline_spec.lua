local outline = require "telescope._extensions.file_browser.outline"

describe("outline extraction", function()
  it("extracts source-ordered top-level JSON keys only", function()
    assert.are.same({
      { text = "name", lnum = 2 },
      { text = "nested", lnum = 3 },
      { text = "enabled", lnum = 4 },
    }, outline.extract("config.json", {
      "{",
      '  "name": "demo",',
      '  "nested": { "ignored": true },',
      '  "enabled": true',
      "}",
    }))
  end)

  it("returns an empty outline for incomplete JSON", function()
    assert.are.same({}, outline.extract("config.json", { '{ "kept": true' }))
  end)

  it("indents Markdown headings and ignores fenced code", function()
    assert.are.same({
      { text = "Guide", lnum = 1 },
      { text = "  Setup", lnum = 2 },
      { text = "    Linux", lnum = 6 },
    }, outline.extract("README.md", {
      "# Guide",
      "## Setup",
      "```python",
      "### ignored",
      "```",
      "### Linux ###",
    }))
  end)

  it("does not close Markdown fences that have trailing content", function()
    assert.are.same({}, outline.extract("README.md", {
      "```",
      "``` trailing",
      "### hidden",
      "```",
    }))
  end)

  it("shows nested Python class and function symbols", function()
    assert.are.same({
      { text = "󰠱 Client", lnum = 1 },
      { text = "  󰊕 fetch", lnum = 2 },
      { text = "    󰊕 parse", lnum = 3 },
      { text = "󰊕 main", lnum = 5 },
    }, outline.extract("client.py", {
      "class Client:",
      "    async def fetch(self):",
      "        def parse():",
      "            pass",
      "def main():",
      "    pass",
    }))
  end)

  it("preserves non-ASCII Python identifiers", function()
    assert.are.same({
      { text = "󰠱 Café", lnum = 1 },
      { text = "  󰊕 résumé", lnum = 2 },
    }, outline.extract("client.py", {
      "class Café:",
      "    def résumé(self):",
      "        pass",
    }))
  end)

  it("supports only requested extensions", function()
    assert.is_true(outline.supports "a.json")
    assert.is_true(outline.supports "a.md")
    assert.is_true(outline.supports "a.markdown")
    assert.is_true(outline.supports "a.py")
    assert.is_false(outline.supports "a.lua")
    assert.is_nil(outline.extract("a.lua", { "return true" }))
  end)
end)

describe("outline previewer", function()
  local original_bufnr
  local previewer

  after_each(function()
    if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
      vim.api.nvim_win_set_buf(0, original_bufnr)
    end
    if previewer then
      previewer:teardown()
    end
    original_bufnr = nil
    previewer = nil
  end)

  it("loads and extracts only the selected file when it is previewed", function()
    local loaded = {}
    previewer = outline.new {
      buffer_previewer_maker = function(path, bufnr, opts)
        table.insert(loaded, path)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
          "{",
          '  "first": true,',
          '  "nested": { "ignored": true }',
          "}",
        })
        opts.callback(bufnr)
      end,
    }

    assert.are.same({}, loaded)

    original_bufnr = vim.api.nvim_get_current_buf()
    local preview_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, preview_bufnr)
    previewer:preview({ path = "/tmp/selected.json" }, { layout = { preview = { winid = 0 } } })

    assert.is_true(vim.wait(1000, function()
      return vim.api.nvim_buf_get_lines(previewer.state.bufnr, 0, -1, false)[1] == "first"
    end, 10))
    assert.are.same({ "/tmp/selected.json" }, loaded)
    assert.are.same({ "first", "nested" }, vim.api.nvim_buf_get_lines(previewer.state.bufnr, 0, -1, false))
  end)

  it("keeps directory previews raw when their names use supported extensions", function()
    previewer = outline.new {
      buffer_previewer_maker = function(_, bufnr, opts)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "child.py", "README.md" })
        opts.callback(bufnr)
      end,
    }

    original_bufnr = vim.api.nvim_get_current_buf()
    local preview_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, preview_bufnr)
    previewer:preview({ path = "/tmp/archive.json", is_dir = true }, { layout = { preview = { winid = 0 } } })

    assert.is_true(vim.wait(1000, function()
      return vim.api.nvim_buf_get_lines(previewer.state.bufnr, 0, -1, false)[1] == "child.py"
    end, 10))
    assert.are.same({ "child.py", "README.md" }, vim.api.nvim_buf_get_lines(previewer.state.bufnr, 0, -1, false))
  end)
end)
