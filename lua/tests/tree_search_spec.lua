local Path = require "plenary.path"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local search = require "telescope._extensions.file_browser.search"
local find_contents = search.find_contents

local root
local prompt_bufnr
local original_cwd

local function path(...)
  return Path:new(root, ...):absolute()
end

local function open_picker(opts)
  local telescope = require "telescope"
  telescope.setup {
    extensions = {
      file_browser = {
        tree = true,
        grouped = true,
        use_fd = false,
        hidden = true,
        respect_gitignore = false,
        git_status = false,
        display_stat = false,
        mappings = {},
      },
    },
  }
  telescope.load_extension "file_browser"
  telescope.extensions.file_browser.file_browser(vim.tbl_extend("force", {
    path = root,
    cwd = root,
    preview = false,
    layout_config = { width = 50, height = 10, prompt_position = "top" },
  }, opts or {}))
  assert.is_true(vim.wait(1000, function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "TelescopePrompt" then
        prompt_bufnr = bufnr
        local picker = action_state.get_current_picker(bufnr)
        return picker and picker.manager and picker.manager:num_results() > 0
      end
    end
  end, 10))
  return action_state.get_current_picker(prompt_bufnr), telescope.extensions.file_browser.actions
end

local function content_search(picker, fb_actions, query, count)
  fb_actions.start_search(prompt_bufnr)
  fb_actions.toggle_search_scope(prompt_bufnr)
  picker:reset_prompt(query)
  fb_actions.confirm_search(prompt_bufnr)
  assert.is_true(vim.wait(2000, function()
    local selected = action_state.get_selected_entry()
    return not picker._tree_searching and picker.finder._content_prompt == query
      and #picker.finder.match_indices == count and selected and selected.lnum ~= nil
  end, 10))
end

describe("tree search", function()
  before_each(function()
    original_cwd = vim.fn.getcwd()
    root = vim.fn.tempname()
    vim.fn.mkdir(path "folder1", "p")
    vim.fn.mkdir(path "folder2", "p")
    local lines = {}
    for index = 1, 85 do
      lines[index] = "filler"
    end
    lines[34] = "needle at the first location"
    lines[1] = "# First heading"
    lines[50] = "# Second heading"
    lines[85] = "needle at the second location"
    vim.fn.writefile(lines, path("folder1", "file1.md"))
    vim.fn.writefile({ "no content hit" }, path("folder1", "needle.txt"))
    vim.fn.writefile({ "needle in another folder" }, path("folder2", "file2.txt"))
  end)

  after_each(function()
    search.find_contents = find_contents
    if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
      pcall(actions.close, prompt_bufnr)
    end
    prompt_bufnr = nil
    vim.api.nvim_set_current_dir(original_cwd)
    vim.fn.delete(root, "rf")
  end)

  it("changes directory from entries without a cached Path object", function()
    local directory = path "folder with spaces"
    local filename = Path:new(directory, "file.txt"):absolute()
    vim.fn.mkdir(directory, "p")
    vim.fn.writefile({ "needle" }, filename)
    local picker, fb_actions = open_picker {
      entry_maker = function()
        return function(absolute_path)
          return {
            value = absolute_path,
            path = absolute_path,
            filename = absolute_path,
            ordinal = absolute_path,
            display = absolute_path,
            is_dir = vim.fn.isdirectory(absolute_path) == 1,
          }
        end
      end,
    }
    for index, entry in ipairs(picker.finder.results) do
      if entry.path == directory then
        picker:set_selection(picker:get_row(index))
        break
      end
    end
    assert.is_nil(action_state.get_selected_entry().Path)
    fb_actions.change_cwd(prompt_bufnr)
    assert.are.same(directory, vim.fn.getcwd())
    assert.are.same(directory, picker.finder.path)
    assert.is_true(vim.wait(1000, function()
      local entry = action_state.get_selected_entry()
      return entry and entry.path == filename
    end, 10))
    assert.is_nil(action_state.get_selected_entry().Path)
    fb_actions.change_cwd(prompt_bufnr)
    assert.are.same(directory, vim.fn.getcwd())
    assert.are.same(directory, picker.finder.path)
  end)

  it("leaves the working directory unchanged when there is no selected result", function()
    local picker, fb_actions = open_picker()
    fb_actions.start_search(prompt_bufnr)
    picker:reset_prompt "no matching filename"
    fb_actions.confirm_search(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return picker.manager:num_results() == 0 and picker:get_selection() == nil
    end, 10))
    fb_actions.change_cwd(prompt_bufnr)
    assert.are.same(original_cwd, vim.fn.getcwd())
    assert.are.same(root, picker.finder.path)
  end)

  it("waits for Enter, cancels drafts, and toggles names and contents", function()
    local picker, fb_actions = open_picker()
    assert.are.same("normal", picker.initial_mode)
    assert.are.same("file", picker._tree_mode)
    assert.is_true(vim.api.nvim_win_is_valid(picker._tree_footer_win))
    assert.is_truthy(picker._tree_footer:find("search", 1, true))
    local initial_results = picker.finder.results

    fb_actions.start_search(prompt_bufnr)
    assert.are.same("search", picker._tree_mode)
    assert.is_truthy(picker._tree_footer:find("Esc cancel", 1, true))
    picker:reset_prompt "needle"
    assert.is_false(vim.wait(50, function()
      return picker.finder.tree_state.search_prompt == "needle"
    end, 10))
    assert.are.equal(initial_results, picker.finder.results)
    fb_actions.cancel_search(prompt_bufnr)
    assert.are.same("", picker:_get_prompt())
    assert.are.same("file", picker._tree_mode)
    assert.is_true(vim.api.nvim_buf_is_valid(prompt_bufnr))

    fb_actions.start_search(prompt_bufnr)
    picker:reset_prompt "needle"
    fb_actions.confirm_search(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      local selected = action_state.get_selected_entry()
      return #picker.finder.results == 2 and selected and selected.path == path("folder1", "needle.txt")
    end, 10))

    fb_actions.toggle_search_scope(prompt_bufnr)
    assert.is_true(vim.wait(2000, function()
      return not picker._tree_searching and #picker.finder.match_indices == 3 and #picker.finder.results == 5
    end, 10))
    assert.are.same("content", picker.finder._tree_search_scope)
    assert.is_truthy(picker.prompt_prefix:find("Content", 1, true))
    local hits = {}
    for _, entry in ipairs(picker.finder.results) do
      if entry.path == path("folder1", "file1.md") then
        table.insert(hits, entry.lnum)
        assert.is_truthy(entry.display(entry):find("file1.md", 1, true))
        assert.is_truthy(entry.display(entry):match(tostring(entry.lnum) .. "$"))
      end
      assert.are_not.same(path("folder1", "needle.txt"), entry.path)
    end
    assert.are.same({ 34, 85 }, hits)
    assert.are.same({ picker._tree_footer }, vim.api.nvim_buf_get_lines(picker._tree_footer_bufnr, 0, -1, false))

    fb_actions.toggle_search_scope(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return picker.finder._tree_search_scope == "names" and #picker.finder.results == 2
    end, 10))
    fb_actions.start_search(prompt_bufnr)
    fb_actions.toggle_search_scope(prompt_bufnr)
    picker:reset_prompt "abandoned query"
    fb_actions.cancel_search(prompt_bufnr)
    assert.are.same("names", picker.finder._tree_search_scope)
    assert.are.same("needle", picker:_get_prompt())
    assert.are.same(2, #picker.finder.results)
  end)

  for _, line in ipairs { 34, 85 } do
    it("opens the selected occurrence at line " .. line, function()
      local picker, fb_actions = open_picker()
      content_search(picker, fb_actions, "needle", 3)
      for index, entry in ipairs(picker.finder.results) do
        if entry.path == path("folder1", "file1.md") and entry.lnum == line then
          picker:set_selection(picker:get_row(index))
          break
        end
      end
      assert.are.same(line, action_state.get_selected_entry().lnum)
      local footer_win = picker._tree_footer_win
      local footer_buf = picker._tree_footer_bufnr
      fb_actions.tree_select(prompt_bufnr)
      assert.are.same(path("folder1", "file1.md"), vim.api.nvim_buf_get_name(0))
      assert.are.same({ line, 0 }, vim.api.nvim_win_get_cursor(0))
      assert.is_false(vim.api.nvim_win_is_valid(footer_win))
      assert.is_false(vim.api.nvim_buf_is_valid(footer_buf))
    end)
  end

  it("keeps more than 250 occurrences of one file navigable", function()
    local lines = {}
    for index = 1, 310 do
      lines[index] = "many occurrences"
    end
    vim.fn.writefile(lines, path("folder1", "file1.md"))
    local picker, fb_actions = open_picker()
    content_search(picker, fb_actions, "many occurrences", 310)
    assert.are.same(311, #picker.finder.results)
    assert.is_true(picker.max_results >= 311)
    assert.are.same(1, action_state.get_selected_entry().lnum)
    fb_actions.previous_match(prompt_bufnr)
    assert.are.same(310, action_state.get_selected_entry().lnum)
    assert.are.same(311, vim.api.nvim_win_get_cursor(picker.results_win)[1])
    local display = vim.api.nvim_buf_get_lines(picker.results_bufnr, 310, 311, false)[1]
    assert.is_truthy(display:find("file1.md", 1, true))
    assert.is_truthy(display:match "310$")
    picker.layout_config.horizontal.height = 7
    picker:full_layout_update()
    assert.are.same(2, vim.api.nvim_win_get_height(picker.results_win))
    assert.are.same(311, vim.api.nvim_win_get_cursor(picker.results_win)[1])
    local position = vim.api.nvim_win_get_position(picker.results_win)
    assert.are.same(position[1] + 2, vim.api.nvim_win_get_position(picker._tree_footer_win)[1])
    assert.is_true(vim.fn.strdisplaywidth(picker._tree_footer) <= vim.api.nvim_win_get_width(picker._tree_footer_win))
  end)

  it("treats selected occurrences of one file as one file operation", function()
    local picker, fb_actions = open_picker()
    content_search(picker, fb_actions, "needle", 3)
    for index, entry in ipairs(picker.finder.results) do
      if entry.path == path("folder1", "file1.md") then
        picker:set_selection(picker:get_row(index))
        actions.toggle_selection(prompt_bufnr)
      end
    end
    assert.are.same(2, #picker:get_multi_selection())
    local files = require("telescope._extensions.file_browser.utils").get_selected_files(prompt_bufnr)
    assert.are.same(1, #files)
    assert.are.same(path("folder1", "file1.md"), files[1]:absolute())
  end)

  it("previews the matching line instead of the file outline", function()
    local picker, fb_actions = open_picker {
      preview = true,
      layout_config = { width = 0.95, preview_cutoff = 0 },
    }
    content_search(picker, fb_actions, "needle", 3)
    for index, entry in ipairs(picker.finder.results) do
      if entry.path == path("folder1", "file1.md") and entry.lnum == 85 then
        picker:set_selection(picker:get_row(index))
        break
      end
    end
    assert.are.same(2, picker.current_previewer_index)
    assert.is_true(vim.wait(1000, function()
      return picker.preview_win and vim.api.nvim_win_get_cursor(picker.preview_win)[1] == 85
    end, 10))
    fb_actions.cycle_tree_mode(prompt_bufnr)
    assert.are.same("outline", picker._tree_mode)
    assert.is_true(vim.wait(1000, function()
      local buffer = vim.api.nvim_win_get_buf(picker.preview_win)
      local headings = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
      return #headings == 2 and headings[1] == "First heading" and headings[2] == "Second heading"
    end, 10))
    assert.are.same(1, vim.api.nvim_win_get_cursor(picker.preview_win)[1])
    fb_actions.tree_next(prompt_bufnr)
    assert.are.same(2, vim.api.nvim_win_get_cursor(picker.preview_win)[1])
    fb_actions.cycle_tree_mode(prompt_bufnr)
    assert.are.same("file", picker._tree_mode)
    assert.are.same(85, action_state.get_selected_entry().lnum)
  end)

  it("discards cancelled requests and resumes a pending search after cancelling a draft", function()
    local requests = {}
    local killed = 0
    search.find_contents = function(_, query, callback)
      table.insert(requests, { query = query, callback = callback })
      return { handle = { kill = function()
        killed = killed + 1
      end } }
    end
    local picker, fb_actions = open_picker()
    fb_actions.start_search(prompt_bufnr)
    fb_actions.toggle_search_scope(prompt_bufnr)
    picker:reset_prompt "first"
    fb_actions.confirm_search(prompt_bufnr)
    fb_actions.tree_select(prompt_bufnr)
    assert.is_true(vim.api.nvim_buf_is_valid(prompt_bufnr))

    fb_actions.start_search(prompt_bufnr)
    picker:reset_prompt "second"
    fb_actions.confirm_search(prompt_bufnr)
    requests[1].callback({ {
      path = path("folder1", "file1.md"), lnum = 34, col = 1, text = "needle at the first location",
    } })
    assert.is_nil(picker.finder._content_prompt)
    requests[2].callback({ {
      path = path("folder1", "file1.md"), lnum = 85, col = 1, text = "needle at the second location",
    } })
    assert.is_true(vim.wait(1000, function()
      local selected = action_state.get_selected_entry()
      return selected and selected.lnum == 85
    end, 10))
    assert.are.same("second", picker.finder._content_prompt)
    assert.are.same(1, killed)

    fb_actions.start_search(prompt_bufnr)
    picker:reset_prompt "first"
    fb_actions.confirm_search(prompt_bufnr)
    fb_actions.start_search(prompt_bufnr)
    picker:reset_prompt "abandoned query"
    fb_actions.cancel_search(prompt_bufnr)
    assert.are.same(4, #requests)
    assert.are.same("first", requests[4].query)
    requests[3].callback({})
    assert.is_nil(picker.finder._content_prompt)
    requests[4].callback({ {
      path = path("folder1", "file1.md"), lnum = 34, col = 1, text = "needle at the first location",
    } })
    assert.is_true(vim.wait(1000, function()
      local selected = action_state.get_selected_entry()
      return selected and selected.lnum == 34
    end, 10))
    assert.are.same("first", picker:_get_prompt())
    assert.are.same("content", picker.finder._tree_search_scope)

    fb_actions.start_search(prompt_bufnr)
    picker:reset_prompt "second"
    fb_actions.confirm_search(prompt_bufnr)
    local footer = picker._tree_footer_win
    actions.close(prompt_bufnr)
    requests[5].callback({})
    assert.is_false(vim.api.nvim_win_is_valid(footer))
    assert.is_false(vim.api.nvim_buf_is_valid(prompt_bufnr))
  end)

  it("uses literal smart-case content searches", function()
    vim.fn.writefile({ "a.b", "aXb", "A.B" }, path "literal.txt")
    local matches
    search.find_contents({ path = root, hidden = false, respect_gitignore = false }, "a.b", function(result)
      matches = result
    end)
    assert.is_true(vim.wait(1000, function()
      return matches ~= nil
    end, 10))
    assert.are.same({ 1, 3 }, vim.tbl_map(function(entry)
      return entry.lnum
    end, matches))
    matches = nil
    search.find_contents({ path = root, hidden = false, respect_gitignore = false }, "A.B", function(result)
      matches = result
    end)
    assert.is_true(vim.wait(1000, function()
      return matches ~= nil
    end, 10))
    assert.are.same(1, #matches)
    assert.are.same(3, matches[1].lnum)
  end)
end)
