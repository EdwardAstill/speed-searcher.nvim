local Tree = require "telescope._extensions.file_browser.tree"

local root = "/project"

local function entry(path, is_dir)
  return {
    path = path,
    value = path,
    ordinal = path:sub(#root + 2),
    is_dir = is_dir,
  }
end

local entries = {
  entry("/project/README.md", false),
  entry("/project/src", true),
  entry("/project/src/main.lua", false),
  entry("/project/src/util", true),
  entry("/project/src/util/parser.lua", false),
  entry("/project/tests", true),
  entry("/project/tests/parser_spec.lua", false),
}

local function paths(projected)
  return vim.tbl_map(function(item)
    return item.path
  end, projected)
end

describe("tree projection", function()
  it("starts with only sorted root children", function()
    local tree = Tree.new(root, entries, { grouped = true })

    assert.are.same({ "/project/src", "/project/tests", "/project/README.md" }, paths(tree:project ""))
  end)

  it("expands and collapses without losing nested state", function()
    local tree = Tree.new(root, entries, { grouped = true })

    assert.is_true(tree:expand "/project/src")
    assert.is_true(tree:expand "/project/src/util")
    assert.is_nil(tree:collapse "/project/src/main.lua")
    assert.are.same({
      "/project/src",
      "/project/src/util",
      "/project/src/util/parser.lua",
      "/project/src/main.lua",
      "/project/tests",
      "/project/README.md",
    }, paths(tree:project ""))

    local collapsed = tree:collapse "/project/src"
    assert.are.same("/project/src", collapsed)
    assert.are.same({
      "/project/src",
      "/project/tests",
      "/project/README.md",
    }, paths(tree:project ""))

    assert.is_true(tree:expand "/project/src")
    assert.are.same({
      "/project/src",
      "/project/src/util",
      "/project/src/util/parser.lua",
      "/project/src/main.lua",
      "/project/tests",
      "/project/README.md",
    }, paths(tree:project ""))
  end)

  it("shows ancestors for a matching file", function()
    local tree = Tree.new(root, entries, { grouped = true })

    assert.are.same({ "/project/src", "/project/src/main.lua" }, paths(tree:project "main"))
  end)

  it("identifies matching rows separately from their tree context", function()
    local tree = Tree.new(root, entries, { grouped = true })

    local projected, match_indices = tree:project "parser"

    assert.are.same({
      "/project/src",
      "/project/src/util",
      "/project/src/util/parser.lua",
      "/project/tests",
      "/project/tests/parser_spec.lua",
    }, paths(projected))
    assert.are.same({ 3, 5 }, match_indices)
  end)

  it("orders direct matches by fuzzy score", function()
    local scored_entries = {
      entry("/project/notes", true),
      entry("/project/notes/knowledge-graphrag.md", false),
      entry("/project/notes/knowledge.md", false),
    }
    local tree = Tree.new(root, scored_entries, { grouped = true })

    local _, match_indices = tree:project "knowledge.md"

    assert.are.same({ 3, 2 }, match_indices)
  end)

  it("shows ancestors and the full subtree for a matching folder", function()
    local tree = Tree.new(root, entries, { grouped = true })

    local projected, match_indices = tree:project "util"

    assert.are.same({
      "/project/src",
      "/project/src/util",
      "/project/src/util/parser.lua",
    }, paths(projected))
    assert.are.same({ 2 }, match_indices)
  end)

  it("collapses and reopens a folder within the current search", function()
    local tree = Tree.new(root, entries, { grouped = true })

    assert.are.same({
      "/project/src",
      "/project/src/util",
      "/project/src/util/parser.lua",
    }, paths(tree:project "util"))

    local search_collapsed = tree:collapse "/project/src"
    assert.are.same("/project/src", search_collapsed)
    assert.are.same({ "/project/src" }, paths(tree:project "util"))

    assert.is_true(tree:expand "/project/src")
    assert.are.same({
      "/project/src",
      "/project/src/util",
      "/project/src/util/parser.lua",
    }, paths(tree:project "util"))

    tree:collapse "/project/src"
    assert.are.same({ "/project/src", "/project/src/main.lua" }, paths(tree:project "main"))
    assert.are.same({ "/project/src", "/project/tests", "/project/README.md" }, paths(tree:project ""))
  end)

  it("deduplicates overlapping search projections", function()
    local tree = Tree.new(root, entries, { grouped = true })

    assert.are.same({
      "/project/src",
      "/project/src/util",
      "/project/src/util/parser.lua",
      "/project/tests",
      "/project/tests/parser_spec.lua",
    }, paths(tree:project "parser"))
  end)

  it("restores manual expansion after clearing search", function()
    local tree = Tree.new(root, entries, { grouped = true })
    tree:expand "/project/tests"

    tree:project "parser"

    assert.are.same({
      "/project/src",
      "/project/tests",
      "/project/tests/parser_spec.lua",
      "/project/README.md",
    }, paths(tree:project ""))
  end)

  it("handles an empty catalog", function()
    local tree = Tree.new(root, {}, { grouped = true })

    assert.are.same({}, tree:project "")
    assert.are.same({}, tree:project "anything")
  end)
end)
