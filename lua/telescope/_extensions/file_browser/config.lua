local fb_actions = require "telescope._extensions.file_browser.actions"
local fb_utils = require "telescope._extensions.file_browser.utils"
local Path = require "plenary.path"

local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"
local telescope_actions = require "telescope.actions"

local config = {}

local cycle_outline_previewer = function(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  if type(picker.all_previewers) == "table" and #picker.all_previewers > 1 then
    picker:cycle_previewers(1)
  end
end

_TelescopeFileBrowserConfig = {
  use_ui_input = true,
  quiet = false,
  tree = false,
  tree_indent = "  ",
  tree_expanded = "",
  tree_collapsed = "",
  tree_mappings = {
    ["i"] = {
      ["<Up>"] = telescope_actions.move_selection_previous,
      ["<Down>"] = telescope_actions.move_selection_next,
      ["<C-Up>"] = fb_actions.previous_match,
      ["<C-Down>"] = fb_actions.next_match,
      ["<Left>"] = fb_actions.collapse,
      ["<Right>"] = fb_actions.expand,
      ["<Tab>"] = cycle_outline_previewer,
      ["<Esc>"] = telescope_actions.close,
    },
  },
  mappings = {
    ["i"] = {
      ["<A-c>"] = fb_actions.create,
      ["<S-CR>"] = fb_actions.create_from_prompt,
      ["<A-r>"] = fb_actions.rename,
      ["<A-m>"] = fb_actions.move,
      ["<A-y>"] = fb_actions.copy,
      ["<A-d>"] = fb_actions.remove,
      ["<C-o>"] = fb_actions.open,
      ["<C-g>"] = fb_actions.goto_parent_dir,
      ["<C-e>"] = fb_actions.goto_home_dir,
      ["<C-w>"] = fb_actions.goto_cwd,
      ["<C-t>"] = fb_actions.change_cwd,
      ["<C-f>"] = fb_actions.toggle_browser,
      ["<C-h>"] = fb_actions.toggle_hidden,
      ["<C-s>"] = fb_actions.toggle_all,
      ["<bs>"] = fb_actions.backspace,
      [Path.path.sep] = fb_actions.path_separator,
    },
    ["n"] = {
      ["c"] = fb_actions.create,
      ["r"] = fb_actions.rename,
      ["m"] = fb_actions.move,
      ["y"] = fb_actions.copy,
      ["d"] = fb_actions.remove,
      ["o"] = fb_actions.open,
      ["g"] = fb_actions.goto_parent_dir,
      ["e"] = fb_actions.goto_home_dir,
      ["w"] = fb_actions.goto_cwd,
      ["t"] = fb_actions.change_cwd,
      ["f"] = fb_actions.toggle_browser,
      ["h"] = fb_actions.toggle_hidden,
      ["s"] = fb_actions.toggle_all,
    },
  },
  attach_mappings = function(prompt_bufnr, map)
    local entry_is_dir = function()
      local entry = action_state.get_selected_entry()
      return entry and fb_utils.is_dir(entry.Path)
    end

    local create_from_prompt = function(prompt_bufnr)
      local picker = action_state.get_current_picker(prompt_bufnr)
      local finder = picker.finder
      local prompt = picker:_get_prompt()
      local entry = action_state.get_selected_entry()
      return not finder.tree and entry == nil and #prompt > 0 and finder.create_from_prompt
    end

    local empty_tree_selection = function()
      local picker = action_state.get_current_picker(prompt_bufnr)
      return picker.finder.tree and action_state.get_selected_entry() == nil
    end

    local select_dir = function(bufnr, select_type)
      local finder = action_state.get_current_picker(bufnr).finder
      if finder.tree then
        return
      end
      fb_actions.open_dir(bufnr, select_type)
    end

    action_set.select:replace_map {
      [empty_tree_selection] = function() end,
      [entry_is_dir] = select_dir,
      [create_from_prompt] = fb_actions.create_from_prompt,
    }

    local finder = action_state.get_current_picker(prompt_bufnr).finder
    if finder.tree then
      local user_mappings = config.values._user_mappings or {}
      local user_mapping_keys = {}
      for mode, mappings in pairs(user_mappings) do
        mode = mode:lower()
        user_mapping_keys[mode] = user_mapping_keys[mode] or {}
        for key in pairs(mappings) do
          key = vim.api.nvim_replace_termcodes(key, true, true, true)
          user_mapping_keys[mode][key] = true
        end
      end
      for mode, mappings in pairs(config.values.tree_mappings) do
        for key, action in pairs(mappings) do
          local mapped = user_mapping_keys[mode:lower()]
          local normalized_key = vim.api.nvim_replace_termcodes(key, true, true, true)
          if not mapped or not mapped[normalized_key] then
            map(mode, key, action)
          end
        end
      end
      for mode, mappings in pairs(user_mappings) do
        for key, action in pairs(mappings) do
          map(mode, key, action)
        end
      end
    end

    return true
  end,
} or _TelescopeFileBrowserConfig

config.values = _TelescopeFileBrowserConfig

local hijack_netrw = function()
  local netrw_bufname

  -- clear FileExplorer appropriately to prevent netrw from launching on folders
  -- netrw may or may not be loaded before telescope-file-browser config
  -- conceptual credits to nvim-tree
  pcall(vim.api.nvim_clear_autocmds, { group = "FileExplorer" })
  vim.api.nvim_create_autocmd("VimEnter", {
    pattern = "*",
    once = true,
    callback = function()
      pcall(vim.api.nvim_clear_autocmds, { group = "FileExplorer" })
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("telescope-file-browser.nvim", { clear = true }),
    pattern = "*",
    callback = function()
      vim.schedule(function()
        if vim.bo[0].filetype == "netrw" then
          return
        end
        local bufname = vim.api.nvim_buf_get_name(0)
        if vim.fn.isdirectory(bufname) == 0 then
          _, netrw_bufname = pcall(vim.fn.expand, "#:p:h")
          return
        end

        -- prevents reopening of file-browser if exiting without selecting a file
        if netrw_bufname == bufname then
          netrw_bufname = nil
          return
        else
          netrw_bufname = bufname
        end

        -- ensure no buffers remain with the directory name
        vim.api.nvim_buf_set_option(0, "bufhidden", "wipe")

        require("telescope").extensions.file_browser.file_browser {
          cwd = vim.fn.expand "%:p:h",
        }
      end)
    end,
    desc = "telescope-file-browser.nvim replacement for netrw",
  })
end

config.setup = function(opts)
  local user_mappings = opts.mappings and vim.deepcopy(opts.mappings) or nil
  -- TODO maybe merge other keys as well from telescope.config
  config.values.mappings =
    vim.tbl_deep_extend("force", config.values.mappings, require("telescope.config").values.mappings)

  if opts.attach_mappings then
    local opts_attach = opts.attach_mappings
    local default_attach = config.values.attach_mappings
    opts.attach_mappings = function(prompt_bufnr, map)
      default_attach(prompt_bufnr, map)
      return opts_attach(prompt_bufnr, map)
    end
  end
  config.values = vim.tbl_deep_extend("force", config.values, opts)
  if user_mappings then
    config.values._user_mappings = user_mappings
  end

  if config.values.hijack_netrw then
    hijack_netrw()
  end
end

return config
