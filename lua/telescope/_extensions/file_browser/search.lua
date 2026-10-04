local Job = require "plenary.job"
local Path = require "plenary.path"
local action_state = require "telescope.actions.state"

local M = {}

function M.update_footer(picker)
  local win = picker.results_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local mode = picker._tree_mode or "file"
  local source = picker.finder._tree_search_scope == "content" and "Content" or "Names"
  local variants
  if picker._tree_searching then
    variants = { "Searching... | / edit | Ctrl+F source | Esc close", "Searching... | Esc close" }
  elseif mode == "search" then
    variants = {
      source .. " | Enter search | Esc cancel | Ctrl+F source",
      "Enter search | Esc cancel | Ctrl+F source",
      "C-f mode Enter search Esc cancel",
      "Enter search | Esc cancel",
    }
  elseif mode == "outline" then
    variants = {
      "Outline | arrows move | Enter jump | Tab files | / search | Ctrl+F source | Esc close",
      "Enter jump | Tab files | / search",
      "C-f mode Enter jump Tab files",
      "Enter jump | Tab files",
    }
  else
    variants = {
      "/ search | Enter open | ↑↓ move | ←→ fold | C-f source | Tab outline | Esc close",
      "/ search | Enter open | Ctrl+F source | Tab outline | Esc close",
      "/ search | Enter open | Ctrl+F source | Esc close",
      "C-f mode / search Enter open Esc close",
      "/ search | Enter open",
    }
  end
  local left, right, bottom
  for _, pane in ipairs { picker.results_win, picker.prompt_win, picker.preview_win } do
    if pane and vim.api.nvim_win_is_valid(pane) then
      local pos = vim.api.nvim_win_get_position(pane)
      left = math.min(left or pos[2], pos[2])
      right = math.max(right or 0, pos[2] + vim.api.nvim_win_get_width(pane))
      bottom = math.max(bottom or 0, pos[1] + vim.api.nvim_win_get_height(pane))
    end
  end
  local width = right - left
  local text = variants[#variants]
  for _, candidate in ipairs(variants) do
    if vim.fn.strdisplaywidth(candidate) <= width then
      text = candidate
      break
    end
  end
  local lines = {}
  if vim.fn.strdisplaywidth(text) > width then
    text = text:sub(1, width)
  end
  picker._tree_footer = text
  lines[1] = text
  if not picker._tree_footer_bufnr or not vim.api.nvim_buf_is_valid(picker._tree_footer_bufnr) then
    picker._tree_footer_bufnr = vim.api.nvim_create_buf(false, true)
  end
  vim.api.nvim_buf_set_lines(picker._tree_footer_bufnr, 0, -1, false, lines)
  local config = {
    relative = "editor",
    row = math.min(bottom, vim.o.lines - vim.o.cmdheight - 1),
    col = left,
    width = width,
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = 60,
  }
  if picker._tree_footer_win and vim.api.nvim_win_is_valid(picker._tree_footer_win) then
    vim.api.nvim_win_set_config(picker._tree_footer_win, config)
  else
    picker._tree_footer_win = vim.api.nvim_open_win(picker._tree_footer_bufnr, false, config)
    vim.wo[picker._tree_footer_win].winhighlight = "Normal:TelescopePromptTitle"
  end
end

function M.find_contents(finder, prompt, callback)
  if prompt == "" then
    callback({}, nil)
    return
  end
  if vim.fn.executable "rg" ~= 1 then
    callback({}, "Content search requires ripgrep (rg)")
    return
  end

  local args = { "--json", "--fixed-strings", "--smart-case", "--glob", "!.git/**" }
  local hidden = finder.hidden
  if type(hidden) == "table" then
    hidden = hidden.file_browser
  end
  if hidden then
    table.insert(args, "--hidden")
  end
  if not finder.respect_gitignore then
    table.insert(args, "--no-ignore-vcs")
  end
  if finder.no_ignore then
    table.insert(args, "--no-ignore")
  end
  if finder.follow_symlinks then
    table.insert(args, "--follow")
  end
  vim.list_extend(args, { "--", prompt, "." })

  local matches = {}
  local errors = {}
  local job = Job:new {
    command = "rg",
    args = args,
    cwd = finder.path,
    enable_recording = false,
    on_stdout = function(_, line)
      local ok, item = pcall(vim.json.decode, line)
      if not ok or item.type ~= "match" or not item.data.path.text or not item.data.lines.text then
        return
      end
      local data = item.data
      local relative = data.path.text:gsub("^%./", "")
      table.insert(matches, {
        path = Path:new(finder.path, relative):absolute(),
        lnum = data.line_number,
        col = data.submatches[1].start + 1,
        colend = data.submatches[1]["end"] + 1,
        text = data.lines.text:gsub("[\r\n]+$", ""),
      })
    end,
    on_stderr = function(_, line)
      table.insert(errors, line)
    end,
    on_exit = vim.schedule_wrap(function(_, code)
      callback(matches, code > 1 and table.concat(errors, "\n") or nil)
    end),
  }
  job:start()
  return job
end

local function stop_search(picker)
  picker._tree_search_id = (picker._tree_search_id or 0) + 1
  if picker._tree_search_job and not picker._tree_search_job.is_shutdown then
    pcall(function()
      picker._tree_search_job.handle:kill(15)
    end)
  end
  picker._tree_search_job = nil
  picker._tree_searching = false
end

function M.update_prefix(picker)
  local source = picker.finder._tree_search_scope == "content" and "Content" or "Names"
  local marker = picker._tree_mode == "search" and "/ " or picker._tree_mode == "outline" and "≡ " or "▸ "
  local query = picker:_get_prompt()
  local attached = picker._finder_attached
  picker._finder_attached = false
  picker:change_prompt_prefix(source .. " " .. marker)
  picker:reset_prompt(query)
  picker._finder_attached = attached
end

function M.start(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  if picker._tree_mode == "search" then
    return
  end
  local pending = picker._tree_searching
  stop_search(picker)
  picker._tree_previous_pending = pending
  picker._tree_previous_query = picker:_get_prompt()
  picker._tree_previous_scope = picker.finder._tree_search_scope or "names"
  picker._finder_attached = false
  picker._tree_mode = "search"
  M.update_prefix(picker)
  M.update_footer(picker)
  vim.cmd.startinsert()
end

function M.cancel(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  local pending = picker._tree_previous_pending
  stop_search(picker)
  picker._tree_mode = "file"
  picker.finder._tree_search_scope = picker._tree_previous_scope or "names"
  M.update_prefix(picker)
  picker:reset_prompt(picker._tree_previous_query or "")
  picker._finder_attached = true
  picker._tree_previous_query = nil
  picker._tree_previous_scope = nil
  picker._tree_previous_pending = nil
  M.update_footer(picker)
  vim.cmd.stopinsert()
  if pending then
    M.confirm(prompt_bufnr)
  end
end

function M.confirm(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  local prompt = picker:_get_prompt()
  stop_search(picker)
  local search_id = picker._tree_search_id
  picker._tree_mode = "file"
  picker._tree_previous_query = nil
  picker._tree_previous_scope = nil
  picker._tree_previous_pending = nil
  picker._finder_attached = false
  M.update_prefix(picker)
  picker._tree_searching = true
  M.update_footer(picker)
  vim.cmd.stopinsert()

  local function complete(matches, err)
    if picker.closed or not vim.api.nvim_buf_is_valid(prompt_bufnr) or picker._tree_search_id ~= search_id then
      return
    end
    picker._tree_searching = false
    picker._tree_search_job = nil
    local tree = picker.finder.tree_state
    if tree then
      tree.search_collapsed = {}
    end
    local hits = {}
    for _, match in ipairs(matches) do
      local base = tree and tree.entries[match.path]
      if base and not base.is_dir then
        local entry = setmetatable(vim.tbl_extend("force", base, match), getmetatable(base))
        hits[match.path] = hits[match.path] or {}
        table.insert(hits[match.path], entry)
      end
    end
    for _, entries in pairs(hits) do
      table.sort(entries, function(left, right)
        return left.lnum < right.lnum
      end)
    end
    picker.finder._content_prompt = prompt
    picker.finder._content_matches = hits
    picker._finder_attached = true
    if err then
      vim.notify(err, vim.log.levels.WARN)
    end
    picker:refresh(nil, { reset_prompt = false })
    M.update_footer(picker)
  end
  if picker.finder._tree_search_scope == "content" then
    picker.finder._content_prompt = nil
    picker:refresh(nil, { reset_prompt = false })
    picker._tree_search_job = M.find_contents(picker.finder, prompt, complete)
  else
    complete({}, nil)
  end
end

function M.toggle_scope(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  local editing = picker._tree_mode == "search"
  if not editing then
    M.start(prompt_bufnr)
  end
  picker.finder._tree_search_scope = picker.finder._tree_search_scope == "content" and "names" or "content"
  M.update_prefix(picker)
  M.update_footer(picker)
  if not editing then
    M.confirm(prompt_bufnr)
  end
end

function M.close(picker)
  stop_search(picker)
  if picker._tree_footer_win and vim.api.nvim_win_is_valid(picker._tree_footer_win) then
    vim.api.nvim_win_close(picker._tree_footer_win, true)
  end
  if picker._tree_footer_bufnr and vim.api.nvim_buf_is_valid(picker._tree_footer_bufnr) then
    vim.api.nvim_buf_delete(picker._tree_footer_bufnr, { force = true })
  end
end

return M
