local M = {}

local class_symbol = "󰠱"
local function_symbol = "󰊕"
local python_identifier = "([%a_\128-\255][%w_\128-\255]*)"

local function extract_json(lines)
  local source = table.concat(lines, "\n")
  if not pcall(vim.json.decode, source) then
    return {}
  end

  local keys = {}
  local root_type
  local object_depth = 0
  local in_string = false
  local escaped = false
  local string_value = {}
  local candidate
  local candidate_line
  local line = 1

  for index = 1, #source do
    local char = source:sub(index, index)
    if char == "\n" then
      line = line + 1
    end
    if in_string then
      if escaped then
        table.insert(string_value, char)
        escaped = false
      elseif char == "\\" then
        table.insert(string_value, char)
        escaped = true
      elseif char == '"' then
        in_string = false
        candidate = table.concat(string_value)
      else
        table.insert(string_value, char)
      end
    elseif char == '"' then
      in_string = true
      escaped = false
      string_value = {}
      candidate_line = line
    elseif char == "{" then
      root_type = root_type or "object"
      object_depth = object_depth + 1
      candidate = nil
    elseif char == "}" then
      object_depth = math.max(0, object_depth - 1)
      candidate = nil
    elseif char == "[" then
      root_type = root_type or "array"
      candidate = nil
    elseif char == "]" or char == "," then
      candidate = nil
    elseif char == ":" then
      if root_type == "object" and object_depth == 1 and candidate then
        local ok, key = pcall(vim.json.decode, '"' .. candidate .. '"')
        table.insert(keys, { text = ok and key or candidate, lnum = candidate_line })
      end
      candidate = nil
    elseif not char:match "%s" then
      candidate = nil
    end
  end

  return keys
end

local function extract_markdown(lines)
  local headings = {}
  local fence_char
  local fence_length

  for index, line in ipairs(lines) do
    local marker, trailing = line:match "^%s*([`~]+)(.*)$"
    local marker_char = marker and marker:sub(1, 1) or nil
    local is_fence = marker
      and #marker >= 3
      and marker:gsub(marker_char, "") == ""

    if is_fence then
      if not fence_char then
        fence_char = marker_char
        fence_length = #marker
      elseif marker_char == fence_char and #marker >= fence_length and trailing:match "^%s*$" then
        fence_char = nil
        fence_length = nil
      end
    elseif not fence_char then
      local hashes, title = line:match "^%s*(#+)%s+(.+)$"
      if hashes and #hashes <= 6 then
        title = title:gsub("%s+#+%s*$", ""):gsub("%s+$", "")
        if title ~= "" then
          table.insert(headings, { text = string.rep("  ", #hashes - 1) .. title, lnum = index })
        end
      end
    end
  end

  return headings
end

local function indentation_width(whitespace)
  local width = 0
  for index = 1, #whitespace do
    if whitespace:sub(index, index) == "\t" then
      width = width + 8 - (width % 8)
    else
      width = width + 1
    end
  end
  return width
end

local function extract_python(lines)
  local definitions = {}
  local stack = {}

  for index, line in ipairs(lines) do
    local whitespace = line:match "^[ \t]*"
    local body = line:sub(#whitespace + 1)
    local name = body:match("^class%s+" .. python_identifier .. "%s*[%(:]")
    local symbol = name and class_symbol or function_symbol
    name = name
      or body:match("^async%s+def%s+" .. python_identifier .. "%s*%(")
      or body:match("^def%s+" .. python_identifier .. "%s*%(")

    if name then
      local indent = indentation_width(whitespace)
      while #stack > 0 and indent <= stack[#stack] do
        table.remove(stack)
      end
      table.insert(definitions, {
        text = string.rep("  ", #stack) .. symbol .. " " .. name,
        lnum = index,
      })
      table.insert(stack, indent)
    end
  end

  return definitions
end

local handlers = {
  json = extract_json,
  md = extract_markdown,
  markdown = extract_markdown,
  py = extract_python,
}

local function extension(path)
  return path:lower():match "%.([^./\\]+)$"
end

---@param path string
---@return boolean
function M.supports(path)
  return handlers[extension(path)] ~= nil
end

---@param path string
---@param lines string[]
---@return {text: string, lnum: integer}[]?
function M.extract(path, lines)
  local handler = handlers[extension(path)]
  return handler and handler(lines) or nil
end

M._entries = {}

---@param path string
---@param entries {text: string, lnum: integer}[]?
function M.cache_entries(path, entries)
  M._entries[path] = entries or {}
end

---@param path string
---@return {text: string, lnum: integer}[]?
function M.cached_entries(path)
  return M._entries[path]
end

---@param opts table?
---@return table
function M.new(opts)
  opts = opts or {}
  local from_entry = require "telescope.from_entry"
  local previewers = require "telescope.previewers"
  local buffer_previewer_maker = opts.buffer_previewer_maker
    or require("telescope.config").values.buffer_previewer_maker

  return previewers.new_buffer_previewer {
    title = "Outline Preview",
    get_buffer_by_name = function(_, entry)
      return from_entry.path(entry, false, false)
    end,
    define_preview = function(self, entry)
      local path = from_entry.path(entry, false, false)
      if not path then
        return
      end

      local is_dir = entry.is_dir
      if is_dir == nil then
        is_dir = vim.fn.isdirectory(path) == 1
      end
      local supported = not is_dir and M.supports(path)
      local cached = self.state.bufname == path
      local preview_opts = opts.preview
      if supported then
        preview_opts = vim.tbl_deep_extend(
          "force",
          {},
          type(opts.preview) == "table" and opts.preview or {},
          { highlight_limit = 0 }
        )
      end

      buffer_previewer_maker(path, self.state.bufnr, {
        bufname = self.state.bufname,
        winid = self.state.winid,
        preview = preview_opts,
        file_encoding = opts.file_encoding,
        callback = function(bufnr)
          if not supported or cached or not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end

          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          local extracted = M.extract(path, lines)
          M.cache_entries(path, extracted)
          local texts = extracted
            and #extracted > 0
            and vim.tbl_map(function(item)
              return item.text
            end, extracted)
            or { "No outline available" }
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, texts)
        end,
      })
    end,
  }
end

return M
