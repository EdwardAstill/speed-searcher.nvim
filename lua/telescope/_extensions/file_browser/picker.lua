---@brief
--- You can use the file browser as follows
---
--- ```lua
--- vim.keymap.set(
---   "n",
---   "<space>fb",
---   "<cmd>Telescope file_browser<CR>",
---   { noremap = true }
--- )
---
--- -- or alternatively using lua functions
--- local picker = require "telescope._extensions.file_browser"
--- vim.api.keymap.set("n", "<space>fb", function()
---   picker.file_browser()
--- end, { noremap = true })
--- ```
--- The `file_browser` picker comes pre-configured with several keymaps:
--- - `<cr>`   : Opens the currently selected file/directory, or creates whatever is in the prompt
--- - `<s-cr>` : Create path in prompt
--- - `/`, `\` : (OS Path separator) When typing filepath, the path separator will open a directory like `<cr>`.
--- - `<A-c>/c`: Create file/folder at current `path` (trailing path separator creates folder)
--- - `<A-r>/r`: Rename multi-selected files/folders
--- - `<A-m>/m`: Move multi-selected files/folders to current `path`
--- - `<A-y>/y`: Copy (multi-)selected files/folders to current `path`
--- - `<A-d>/d`: Delete (multi-)selected files/folders
--- - `<C-o>/o`: Open file/folder with default system application
--- - `<C-g>/g`: Go to parent directory
--- - `<C-e>/e`: Go to home directory
--- - `<C-w>/w`: Go to current working directory (cwd)
--- - `<C-t>/t`: Change nvim's cwd to selected folder/file(parent)
--- - `<C-f>/f`: Toggle between file and folder browser
--- - `<C-h>/h`: Toggle hidden files/folders
--- - `<C-s>/s`: Toggle all entries ignoring `./` and `../`
--- - `<bs>/`  : Goes to parent dir if prompt is empty, otherwise acts normally
---
---
--- The file browser picker can be configured with the following options:

local pickers = require "telescope.pickers"
local EntryManager = require "telescope.entry_manager"
local conf = require("telescope.config").values

local fb_finder = require "telescope._extensions.file_browser.finders"
local fb_outline = require "telescope._extensions.file_browser.outline"
local fb_search = require "telescope._extensions.file_browser.search"
local fb_utils = require "telescope._extensions.file_browser.utils"

local Path = require "plenary.path"
local os_sep = Path.path.sep

-- enclose in module for docgen
local fb_picker = {}

local function reveal_tree_context(picker)
  local entry = picker:get_selection()
  local win = picker.results_win
  local row = picker._selection_row
  local tree = picker.finder.tree_state
  if not entry or row == nil or not tree or not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local line = row + 1
  local height = vim.api.nvim_win_get_height(win)
  local topline = math.max(1, line - math.floor((height - 1) / 2))
  -- Leave room below an expanded directory to show its children.
  local context_height = height - (entry.is_dir and entry._tree_expanded and height > 1 and 1 or 0)
  local parent = tree:parent(entry.path)
  while parent and parent ~= tree.root do
    local index = picker.manager:find_entry(tree.entries[parent])
    if not index or line - index >= context_height then
      break
    end
    topline = math.min(topline, index)
    parent = tree:parent(parent)
  end

  vim.wo[win].scrolloff = 0
  vim.api.nvim_win_call(win, function()
    -- Telescope can reset the cursor even when the selected entry is unchanged.
    vim.fn.winrestview { lnum = line, col = 0, topline = topline, leftcol = 0, skipcol = 0 }
  end)
end

local function configure_tree_picker(picker)
  picker._tree_mode = "file"
  picker.prompt_prefix = "Names ▸ "
  picker.finder._on_tree_results = function(count)
    if count > picker.max_results then
      -- Context rows must not consume Telescope's fixed 250-row scrolling limit.
      picker.max_results = count
      picker.__scrolling_limit = count
      picker.manager = EntryManager:new(count, picker.entry_adder, picker.stats)
    end
  end

  local set_selection = picker.set_selection
  picker.set_selection = function(self, row)
    set_selection(self, row)
    reveal_tree_context(self)
    local entry = self:get_selection()
    if
      entry and entry.lnum and self._tree_mode ~= "outline"
      and self.current_previewer_index == 1 and type(self.all_previewers) == "table" and #self.all_previewers > 1
    then
      self:cycle_previewers(1)
    end
    fb_search.update_footer(self)
  end
  local full_layout_update = picker.full_layout_update
  picker.full_layout_update = function(self)
    full_layout_update(self)
    reveal_tree_context(self)
    fb_search.update_footer(self)
  end
  local close_windows = picker.close_windows
  picker.close_windows = function(status)
    fb_search.close(picker)
    close_windows(status)
  end
end

-- try to get the index of entry of current buffer

--- Options for the base telescope picker.
---
--- This should eventually be moved up to telescope core
---@nodoc
---@class telescope.picker.opts
---@field prompt_title string? title of the prompt window
---@field results_title string? title of the results windows
---@field preview_title string? title of the preview window
---@field prompt_prefix string? prefix of the prompt
---@field wrap_results boolean?
---@field selection_caret string?
---@field entry_prefix string?
---@field multi_icon string?
---@field initial_mode ('insert'|'normal')?
---@field debounce number?
---@field default_text string?
---@field get_status_text (fun(picker: table): string)?
---@field on_input_filter_cb (fun(prompt: string): any)?
---@field finder table?
---@field sorter Sorter?
---@field previewer (table)?
---@field current_previewer_index number?
---@field default_selection_index number?
---@field get_selection_window (fun(picker: table, entry: table): number)?
---@field cwd string?
---@field _completion_callbacks ((fun(picker: table): nil)[])?
---@field manager table?
---@field _multi table?
---@field track boolean?
---@field attach_mappings (fun(prompt_bufnr: integer, map: fun()): boolean)?
---@field file_ignore_patterns (string[])?
---@field scroll_strategy ('cycle'|'limit')?
---@field sorting_strategy ('descending'|'ascending')?
---@field tiebreak (fun(current_entry: any, existing_entry: any, prompt: string): boolean)?
---@field selection_strategy ('reset'|'follow'|'row'|'closest'|'none')?
---@field push_cursor_on_edit boolean?
---@field push_tagstack_on_edit boolean?
---@field layout_strategy ('horizontal'|'vertical'|'center'|'cursor'|'flex'|'bottom_pane')?
---@field layout_config table?
---@field cycle_layout_list (string[])?
---@field winblend number?
---@field window table?
---@field border boolean?
---@field borderchars (string[])?

--- Options for the file browser picker.
---
--- Inherits options for the base telescope picker.<br>
--- See |telescope.defaults|
---
--- Notes:
--- - display_stat:
---   - A table that can currently hold `date` and/or `size` as keys -- order matters!
---   - To opt-out, you can pass { display_stat = false }; sorting by stat works regardlessly
---   - The value of a key can be one of `true` or a table of `{ width = integer, display = function, hl = string }`
---   - The flags can be incrementally changed via eg `{ date = true, size = { width = 21, hl = "ErrorMsg" } }`
---   - See make_entry.lua for an example on how to further customize
---@class telescope-file-browser.PickerOpts : telescope.picker.opts
---@field path string: dir to browse files from, `vim.fn.expanded` automatically (default: `vim.loop.cwd()`)
---@field cwd string: dir to browse folders from, `vim.fn.expanded` automatically (default: `vim.loop.cwd()`)
---@field cwd_to_path boolean: whether folder browser is launched from `path` rather than `cwd` (default: `false`)
---@field grouped boolean: group initial sorting by directories and then files (default: `false`)
---@field files boolean: start in file (true) or folder (false) browser (default: `true`)
---@field tree boolean: display a fixed-root expandable tree (default: `false`)
---@field tree_indent string: indentation for each tree depth (default: `"  "`)
---@field tree_expanded string: marker for expanded directories (default: `""`)
---@field tree_collapsed string: marker for collapsed directories (default: `""`)
---@field add_dirs boolean: whether the file browser shows folders (default: `true`)
---@field depth number: file tree depth to display, `false` for unlimited depth (default: `1`)
---@field auto_depth boolean|number: unlimit or set `depth` to `auto_depth` & unset grouped on prompt for file_browser (default: `false`)
---@field select_buffer boolean: select current buffer if possible; may imply `hidden=true` (default: `false`)
---@field hidden table|boolean: determines whether to show hidden files or not (default: `{ file_browser = false, folder_browser = false }`)
---@field respect_gitignore boolean: induces slow-down w/ plenary finder (default: `false`, `true` if `fd` available)
---@field no_ignore boolean: disable use of ignore files like .gitignore/.ignore/.fdignore (default: `false, requires `fd``)
---@field follow_symlinks boolean: traverse symbolic links, i.e. files and folders (default: `false`, only works with `fd`)
---@field browse_files function: custom override for the file browser (default: |fb_finders.browse_files|)
---@field browse_folders function: custom override for the folder browser (default: |fb_finders.browse_folders|)
---@field hide_parent_dir boolean: hide `../` in the file browser (default: `false`)
---@field collapse_dirs boolean: skip dirs w/ only single (possibly hidden) sub-dir in file_browser (default: `false`)
---@field quiet boolean: surpress any notification from file_brower actions (default: `false`)
---@field use_ui_input boolean: Use vim.ui.input() instead of vim.fn.input() or vim.fn.confirm() (default: `true`)
---@field dir_icon string: change the icon for a directory (default: `""`)
---@field dir_icon_hl string: change the highlight group of dir icon (default: `"Default"`)
---@field display_stat boolean|table: ordered stat; see above notes, (default: `{ date = true, size = true, mode = true }`)
---@field use_fd boolean: use `fd` if available over `plenary.scandir` (default: `true`)
---@field git_status boolean: show the git status of files (default: `true` if `git` executable can be found)
---@field prompt_path boolean: Show the current relative path from cwd as the prompt prefix. (default: `false`)
---@field create_from_prompt boolean: Create file/folder from prompt if no entry selected (default: `true`)
---@field theme string?: theme to use for the file browser (default: `nil`)
---@field _custom_prompt_title boolean
---@field _custom_results_title boolean

--- Create a new file browser picker.
---@param opts telescope-file-browser.PickerOpts?: options to pass to the picker
fb_picker.file_browser = function(opts)
  opts = opts or {}

  local cwd = vim.loop.cwd() ---@cast cwd string
  opts.depth = vim.F.if_nil(opts.depth, 1)
  opts.cwd_to_path = vim.F.if_nil(opts.cwd_to_path, false)
  opts.cwd = opts.cwd and fb_utils.to_absolute_path(opts.cwd) or cwd
  opts.path = opts.path and fb_utils.to_absolute_path(opts.path) or opts.cwd
  opts.files = vim.F.if_nil(opts.files, true)
  opts.tree = vim.F.if_nil(opts.tree, false)
  opts.tree_indent = vim.F.if_nil(opts.tree_indent, "  ")
  opts.tree_expanded = vim.F.if_nil(opts.tree_expanded, "")
  opts.tree_collapsed = vim.F.if_nil(opts.tree_collapsed, "")
  opts.initial_mode = opts.tree and "normal" or opts.initial_mode
  opts.sorting_strategy = opts.tree and "ascending" or opts.sorting_strategy
  opts.quiet = vim.F.if_nil(opts.quiet, false)
  opts.hide_parent_dir = vim.F.if_nil(opts.hide_parent_dir, false)
  opts.select_buffer = vim.F.if_nil(opts.select_buffer, false)
  opts.display_stat = vim.F.if_nil(opts.display_stat, { mode = true, date = true, size = true })
  if opts.tree and opts.display_stat then
    local size = type(opts.display_stat) == "table" and opts.display_stat.size or true
    opts.display_stat = { size = size or true }
  end
  opts._custom_prompt_title = opts.prompt_title ~= nil
  opts._custom_results_title = opts.results_title ~= nil
  opts.use_fd = vim.F.if_nil(opts.use_fd, true)
  if opts.tree then
    opts.git_status = false
    opts.wrap_results = false
  else
    opts.git_status = vim.F.if_nil(opts.git_status, vim.fn.executable "git" == 1)
  end
  opts.prompt_path = vim.F.if_nil(opts.prompt_path, false)
  opts.create_from_prompt = vim.F.if_nil(opts.create_from_prompt, true)

  local select_buffer = opts.select_buffer and opts.files
  -- handle case that current buffer is a hidden file
  opts.hidden = (select_buffer and vim.fn.expand("%:p:t"):sub(1, 1) == ".") and true or opts.hidden

  ---@cast opts telescope-file-browser.FinderOpts
  opts.finder = fb_finder.finder(opts)
  if opts.tree then
    opts._completion_callbacks = vim.F.if_nil(opts._completion_callbacks, {})
    table.insert(opts._completion_callbacks, function(current_picker)
      if current_picker:_get_prompt() == "" then
        return
      end

      local finder = current_picker.finder
      local first_match = finder.match_indices and finder.match_indices[1]
      local entry = first_match and finder.results[first_match]
      local result_index = entry and current_picker.manager:find_entry(entry)
      if result_index then
        current_picker:set_selection(current_picker:get_row(result_index))
      end
    end)
  end
  -- find index of current buffer in the results
  if select_buffer then
    local buf_name = vim.api.nvim_buf_get_name(0)
    fb_utils.selection_callback(opts, buf_name)
    -- opts._completion_callbacks = vim.F.if_nil(opts._completion_callbacks, {})
    -- table.insert(opts._completion_callbacks, function(current_picker)
    --   local finder = current_picker.finder
    --   local selection_index = fb_utils._get_selection_index(buf_name, finder.path, finder.results)
    --   if selection_index ~= 1 then
    --     current_picker:set_selection(current_picker:get_row(selection_index))
    --   end
    --   table.remove(current_picker._completion_callbacks)
    -- end)
  end

  local previewer = opts.tree and conf.grep_previewer(opts) or conf.file_previewer(opts)
  if opts.tree and previewer then
    previewer = { fb_outline.new(opts), previewer }
  end

  local picker = pickers.new(opts, {
    prompt_title = opts.tree and "Tree Browser" or (opts.files and "File Browser" or "Folder Browser"),
    results_title = Path:new(opts.path):make_relative(cwd) .. os_sep,
    prompt_prefix = fb_utils.relative_path_prefix(opts.finder),
    previewer = previewer,
    sorter = opts.tree and require("telescope.sorters").highlighter_only(opts) or conf.file_sorter(opts),
  })
  if opts.tree then
    configure_tree_picker(picker)
  end
  picker:find()
end

return fb_picker.file_browser
