local Path = require "plenary.path"

local actions = require "telescope.actions"
local action_set = require "telescope.actions.set"
local action_state = require "telescope.actions.state"

local root
local prompt_bufnr

local function find_prompt()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "TelescopePrompt" then
      return bufnr
    end
  end
end

describe("tree picker", function()
  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(Path:new(root, "src"):absolute(), "p")
    vim.fn.writefile({ "return true" }, Path:new(root, "src", "child.lua"):absolute())
    vim.fn.writefile({ "project" }, Path:new(root, "README.md"):absolute())
  end)

  after_each(function()
    if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
      pcall(actions.close, prompt_bufnr)
    end
    prompt_bufnr = nil
    vim.fn.delete(root, "rf")
  end)

  it("keeps a fixed root and exposes tree controls", function()
    local telescope = require "telescope"
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          grouped = true,
          hidden = true,
          use_fd = false,
          git_status = false,
          display_stat = false,
          mappings = {},
        },
      },
    }
    telescope.load_extension "file_browser"
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
      previewer = false,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      if not prompt_bufnr then
        return false
      end
      local picker = action_state.get_current_picker(prompt_bufnr)
      return picker and picker.finder.tree_state and #picker.finder.results > 0
    end, 10))

    local picker = action_state.get_current_picker(prompt_bufnr)
    assert.are.same("insert", picker.initial_mode)
    assert.is_true(action_state.get_selected_entry().is_dir)
    assert.are.same(2, #picker.all_previewers)
    assert.are.same(1, picker.current_previewer_index)

    action_set.select(prompt_bufnr, "default")

    assert.are.same(root, picker.finder.path)
    assert.is_true(vim.api.nvim_buf_is_valid(prompt_bufnr))

    local fb_actions = telescope.extensions.file_browser.actions
    assert.is_not_nil(fb_actions.expand)
    assert.is_not_nil(fb_actions.collapse)

    local insert_maps = vim.api.nvim_buf_get_keymap(prompt_bufnr, "i")
    local mapped = {}
    for _, mapping in ipairs(insert_maps) do
      mapped[mapping.lhs] = mapping
    end
    assert.is_not_nil(mapped["<Up>"])
    assert.is_not_nil(mapped["<Down>"])
    assert.is_not_nil(mapped["<Left>"])
    assert.is_not_nil(mapped["<Right>"])
    assert.is_not_nil(mapped["<CR>"])
    assert.is_not_nil(mapped["<Esc>"])
    assert.is_not_nil(mapped["<Tab>"])
    assert.is_nil(mapped["/"])
    assert.is_nil(mapped["<BS>"])

    local normal_mapped = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, "n")) do
      normal_mapped[mapping.lhs] = mapping
    end
    assert.is_not_nil(normal_mapped["<Tab>"])
    assert.is_not_nil(normal_mapped[" "])
    assert.is_not_nil(normal_mapped["o"])

    local search_prefix = picker.prompt_prefix
    mapped["<Tab>"].callback(prompt_bufnr)
    assert.are.same("file", picker._tree_mode)
    assert.are_not.same(search_prefix, picker.prompt_prefix)
    normal_mapped["<Tab>"].callback(prompt_bufnr)
    assert.are.same("search", picker._tree_mode)
    assert.are.same(search_prefix, picker.prompt_prefix)

    normal_mapped["o"].callback(prompt_bufnr)
    assert.are.same(2, picker.current_previewer_index)

    local src = Path:new(root, "src"):absolute()
    local child = Path:new(root, "src", "child.lua"):absolute()
    mapped["<Right>"].callback(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 3
    end, 10))
    assert.is_true(picker.finder.tree_state.expanded[src])
    assert.are.same(src, action_state.get_selected_entry().path)

    picker:reset_prompt "child"
    mapped["<Left>"].callback(prompt_bufnr)
    picker:reset_prompt ""
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 3 and picker.finder.tree_state.expanded[src] == true
    end, 10))

    mapped["<Down>"].callback(prompt_bufnr)
    assert.are.same(child, action_state.get_selected_entry().path)
    mapped["<Left>"].callback(prompt_bufnr)
    assert.is_true(picker.finder.tree_state.expanded[src])
    assert.are.same(child, action_state.get_selected_entry().path)
    mapped["<Up>"].callback(prompt_bufnr)
    assert.are.same(src, action_state.get_selected_entry().path)
    mapped["<Left>"].callback(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 2
    end, 10))
    assert.are.same(src, action_state.get_selected_entry().path)

    local missing = Path:new(root, "missing.lua")
    picker:reset_prompt "missing.lua"
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 0
    end, 10))
    mapped["<CR>"].callback(prompt_bufnr)
    assert.is_false(missing:exists())

    picker:reset_prompt ""
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 2
    end, 10))
    mapped["<Right>"].callback(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 3
    end, 10))
    mapped["<Down>"].callback(prompt_bufnr)
    assert.are.same(child, action_state.get_selected_entry().path)
    action_set.select(prompt_bufnr, "default")
    assert.is_true(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(prompt_bufnr)
    end, 10))
    assert.are.same(child, vim.api.nvim_buf_get_name(0))
  end)

  it("shows only icons, names, and sizes in tree rows", function()
    vim.fn.mkdir(Path:new(root, "src", "nested"):absolute(), "p")
    vim.fn.system { "git", "-C", root, "init", "--quiet" }
    assert.are.same(0, vim.v.shell_error)

    local telescope = require "telescope"
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          grouped = true,
          use_fd = false,
          git_status = true,
          git_icons = { untracked = "G" },
          dir_icon = "D",
          tree_collapsed = ">",
          display_stat = {
            mode = {
              width = 4,
              display = function()
                return "MODE"
              end,
            },
            size = true,
            date = {
              width = 4,
              display = function()
                return "DATE"
              end,
            },
          },
          mappings = {},
        },
      },
    }
    telescope.load_extension "file_browser"
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
      previewer = false,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      if not prompt_bufnr then
        return false
      end
      local picker = action_state.get_current_picker(prompt_bufnr)
      return picker and picker.finder.tree_state and #picker.finder.results > 0
    end, 10))

    local picker = action_state.get_current_picker(prompt_bufnr)
    local src_path = Path:new(root, "src"):absolute()
    local src
    for _, entry in ipairs(picker.finder.results) do
      if entry.path == src_path then
        src = entry
        break
      end
    end

    assert.is_not_nil(src)
    local folder_display = src.display(src)
    assert.matches("^>%s+D%s+src%s+2$", folder_display)

    assert.is_true(picker.finder.tree_state:expand(src_path))
    local projected = picker.finder.tree_state:project ""
    local child_path = Path:new(root, "src", "child.lua"):absolute()
    local child
    for _, entry in ipairs(projected) do
      if entry.path == child_path then
        child = entry
        break
      end
    end

    assert.is_not_nil(child)
    local file_display = child.display(child)
    assert.matches("child%.lua%s+12$", file_display)
    assert.is_nil(file_display:find "MODE")
    assert.is_nil(file_display:find "DATE")
    assert.is_nil(file_display:find "G")
  end)

  it("updates search live while arrow keys navigate the tree", function()
    local telescope = require "telescope"
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          grouped = true,
          use_fd = false,
          git_status = false,
          display_stat = false,
          mappings = {},
        },
      },
    }
    telescope.load_extension "file_browser"
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
      previewer = false,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      if not prompt_bufnr then
        return false
      end
      local picker = action_state.get_current_picker(prompt_bufnr)
      return picker and picker.finder.tree_state and #picker.finder.results > 0
    end, 10))

    local picker = action_state.get_current_picker(prompt_bufnr)
    for _, search in ipairs {
      { query = "r", count = 3 },
      { query = "re", count = 1 },
      { query = "rea", count = 1 },
      { query = "read", count = 1 },
    } do
      picker:reset_prompt(search.query)
      assert.is_true(vim.wait(1000, function()
        return picker:_get_prompt() == search.query
          and #picker.finder.results == search.count
          and picker.manager:num_results() == search.count
      end, 10))
    end

    local child = Path:new(root, "src", "child.lua"):absolute()
    picker:reset_prompt "child"
    assert.is_true(vim.wait(1000, function()
      local second = picker.manager:get_entry(2)
      local selected = action_state.get_selected_entry()
      return #picker.finder.results == 2 and second and second.path == child and selected and selected.path == child
    end, 10))
    assert.are.same(child, action_state.get_selected_entry().path)

    local function mappings(mode)
      local mapped = {}
      for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, mode)) do
        mapped[mapping.lhs] = mapping
      end
      return mapped
    end

    local insert_mapped = mappings "i"
    assert.is_not_nil(insert_mapped["<Up>"])
    assert.is_not_nil(insert_mapped["<Down>"])
    assert.is_not_nil(insert_mapped["<C-Up>"])
    assert.is_not_nil(insert_mapped["<C-Down>"])
    assert.is_not_nil(insert_mapped["<Left>"])
    assert.is_not_nil(insert_mapped["<Right>"])
    assert.is_not_nil(insert_mapped["<CR>"])
    assert.is_nil(insert_mapped["/"])
    assert.is_nil(insert_mapped["<BS>"])

    insert_mapped["<Up>"].callback(prompt_bufnr)
    assert.are.same(Path:new(root, "src"):absolute(), action_state.get_selected_entry().path)
    insert_mapped["<Left>"].callback(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 1 and picker.manager:num_results() == 1
    end, 10))
    assert.are.same("child", picker:_get_prompt())

    insert_mapped["<Right>"].callback(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 2 and picker.manager:num_results() == 2
    end, 10))
    assert.are.same(Path:new(root, "src"):absolute(), action_state.get_selected_entry().path)
    insert_mapped["<Down>"].callback(prompt_bufnr)
    assert.are.same("child", picker:_get_prompt())
    assert.are.same(child, action_state.get_selected_entry().path)

    insert_mapped["<CR>"].callback(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(prompt_bufnr)
    end, 10))
    assert.are.same(child, vim.api.nvim_buf_get_name(0))
  end)

  it("wraps Control-arrow navigation across matching rows", function()
    vim.fn.mkdir(Path:new(root, "tests"):absolute(), "p")
    local first_match = Path:new(root, "src", "child.lua"):absolute()
    local second_match = Path:new(root, "tests", "child_spec.lua"):absolute()
    vim.fn.writefile({ "return true" }, second_match)

    local telescope = require "telescope"
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          grouped = true,
          use_fd = false,
          git_status = false,
          display_stat = false,
          mappings = {},
        },
      },
    }
    telescope.load_extension "file_browser"
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
      previewer = false,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      if not prompt_bufnr then
        return false
      end
      local picker = action_state.get_current_picker(prompt_bufnr)
      return picker and picker.finder.tree_state and #picker.finder.results > 0
    end, 10))

    local picker = action_state.get_current_picker(prompt_bufnr)
    picker:reset_prompt "child"
    assert.is_true(vim.wait(1000, function()
      local selected = action_state.get_selected_entry()
      return #picker.finder.results == 4 and selected and selected.path == first_match
    end, 10))

    local mapped = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, "i")) do
      mapped[mapping.lhs] = mapping
    end

    mapped["<C-Down>"].callback(prompt_bufnr)
    assert.are.same(second_match, action_state.get_selected_entry().path)
    mapped["<C-Down>"].callback(prompt_bufnr)
    assert.are.same(first_match, action_state.get_selected_entry().path)
    mapped["<C-Up>"].callback(prompt_bufnr)
    assert.are.same(second_match, action_state.get_selected_entry().path)
  end)

  it("allows disabling tree mappings with equivalent key names", function()
    local telescope = require "telescope"
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          use_fd = false,
          git_status = false,
          display_stat = false,
          mappings = {
            i = {
              ["<cr>"] = false,
              ["<esc>"] = false,
              ["<up>"] = false,
              ["<down>"] = false,
              ["<c-up>"] = false,
              ["<c-down>"] = false,
              ["<left>"] = false,
              ["<right>"] = false,
            },
          },
        },
      },
    }
    telescope.load_extension "file_browser"
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
      previewer = false,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      return prompt_bufnr ~= nil
    end, 10))

    local insert_mapped = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, "i")) do
      insert_mapped[mapping.lhs] = mapping
    end
    assert.is_nil(insert_mapped["<CR>"])
    assert.is_nil(insert_mapped["<Esc>"])
    assert.is_nil(insert_mapped["<Up>"])
    assert.is_nil(insert_mapped["<Down>"])
    assert.is_nil(insert_mapped["<C-Up>"])
    assert.is_nil(insert_mapped["<C-Down>"])
    assert.is_nil(insert_mapped["<Left>"])
    assert.is_nil(insert_mapped["<Right>"])
  end)

  it("ignores the outline toggle when previews are disabled", function()
    local telescope = require "telescope"
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          grouped = true,
          use_fd = false,
          preview = false,
          mappings = {},
        },
      },
    }
    telescope.load_extension "file_browser"
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      return prompt_bufnr ~= nil
    end, 10))
    local normal_mapped = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, "n")) do
      normal_mapped[mapping.lhs] = mapping
    end

    assert.is_not_nil(normal_mapped["o"])
    assert.has_no.errors(function()
      normal_mapped["o"].callback(prompt_bufnr)
    end)
  end)

  it("closes the picker with Escape from search input", function()
    local telescope = require "telescope"
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          use_fd = false,
          git_status = false,
          display_stat = false,
          mappings = {},
        },
      },
    }
    telescope.load_extension "file_browser"
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
      previewer = false,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      return prompt_bufnr ~= nil
    end, 10))

    local insert_mapped = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, "i")) do
      insert_mapped[mapping.lhs] = mapping
    end
    assert.is_not_nil(insert_mapped["<Esc>"])
    insert_mapped["<Esc>"].callback(prompt_bufnr)

    assert.is_true(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(prompt_bufnr)
    end, 10))
  end)

  it("cycles into outline mode and opens files at outline entries", function()
    local telescope = require "telescope"
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          grouped = true,
          hidden = true,
          use_fd = false,
          git_status = false,
          display_stat = false,
          mappings = {},
        },
      },
    }
    telescope.load_extension "file_browser"
    local doc = Path:new(root, "notes.md")
    vim.fn.writefile({ "# Alpha", "text", "## Beta", "more" }, doc:absolute())
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      return prompt_bufnr ~= nil
    end, 10))

    local picker = action_state.get_current_picker(prompt_bufnr)
    local mapped = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, "i")) do
      mapped[mapping.lhs] = mapping
    end

    picker:reset_prompt "notes"
    assert.is_true(vim.wait(1000, function()
      local selected = action_state.get_selected_entry()
      return selected and selected.path == doc:absolute()
    end, 10))

    mapped["<Tab>"].callback(prompt_bufnr)
    assert.are.same("file", picker._tree_mode)
    mapped["<Tab>"].callback(prompt_bufnr)
    assert.are.same("outline", picker._tree_mode)
    assert.are.same(1, picker.current_previewer_index)

    local normal_mapped = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, "n")) do
      normal_mapped[mapping.lhs] = mapping
    end
    normal_mapped["<Down>"].callback(prompt_bufnr)
    assert.are.same(2, picker._outline_index)

    normal_mapped["<CR>"].callback(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(prompt_bufnr)
    end, 10))
    assert.is_true(vim.wait(1000, function()
      return vim.api.nvim_buf_get_name(0) == doc:absolute() and vim.api.nvim_win_get_cursor(0)[1] == 3
    end, 10))
    assert.are.same(doc:absolute(), vim.api.nvim_buf_get_name(0))
    assert.are.same(3, vim.api.nvim_win_get_cursor(0)[1])
  end)

end)
