local fzy = require "telescope.algos.fzy"
local Path = require "plenary.path"

local fb_utils = require "telescope._extensions.file_browser.utils"

local Tree = {}
Tree.__index = Tree

local function normalize(path)
  return fb_utils.sanitize_path_str(path)
end

local function sort_children(children, grouped)
  table.sort(children, function(left, right)
    if grouped and left.is_dir ~= right.is_dir then
      return left.is_dir
    end

    local left_path = left.path:lower()
    local right_path = right.path:lower()
    if left_path == right_path then
      return left.path < right.path
    end
    return left_path < right_path
  end)
end

---@class telescope-file-browser.Tree
---@field root string
---@field entries table<string, table>
---@field children table<string, table[]>
---@field parents table<string, string>
---@field expanded table<string, boolean>
---@field search_prompt string
---@field search_collapsed table<string, boolean>
---@field grouped boolean

---@param root string
---@param entries table[]
---@param opts table?
---@return telescope-file-browser.Tree
function Tree.new(root, entries, opts)
  opts = opts or {}
  root = normalize(root)

  local self = setmetatable({
    root = root,
    entries = {},
    children = { [root] = {} },
    parents = {},
    expanded = {},
    search_prompt = "",
    search_collapsed = {},
    grouped = vim.F.if_nil(opts.grouped, false),
  }, Tree)

  for _, entry in ipairs(entries) do
    local path = normalize(entry.path)
    if path ~= root then
      local parent = normalize(Path:new(path):parent():absolute())
      entry.path = path
      entry.value = path
      self.entries[path] = entry
      self.parents[path] = parent
      self.children[parent] = self.children[parent] or {}
      self.children[path] = self.children[path] or {}
      table.insert(self.children[parent], entry)
    end
  end

  for _, children in pairs(self.children) do
    sort_children(children, self.grouped)
  end

  return self
end

---@param path string
---@return string?
function Tree:parent(path)
  return self.parents[normalize(path)]
end

---@param path string
---@param prompt string?
---@return boolean
function Tree:expand(path, prompt)
  if prompt ~= nil then
    self:sync_prompt(prompt)
  end
  path = normalize(path)
  local entry = self.entries[path]
  if not entry or not entry.is_dir or #(self.children[path] or {}) == 0 then
    return false
  end

  if self.search_prompt ~= "" then
    local collapsed = self.search_collapsed[path] == true
    self.search_collapsed[path] = nil
    return collapsed
  end

  self.expanded[path] = true
  return true
end

---@param path string
---@param prompt string?
---@return string?
function Tree:collapse(path, prompt)
  if prompt ~= nil then
    self:sync_prompt(prompt)
  end
  path = normalize(path)
  local entry = self.entries[path]
  if not entry or not entry.is_dir then
    return
  end

  if self.search_prompt ~= "" then
    if #(self.children[path] or {}) == 0 or self.search_collapsed[path] then
      return
    end
    self.search_collapsed[path] = true
    return path
  end

  if self.expanded[path] then
    self.expanded[path] = nil
    return path
  end
end

local function set_metadata(entry, depth, expanded, has_children, child_count)
  entry._tree_depth = depth
  entry._tree_expanded = expanded
  entry._tree_has_children = has_children
  entry._tree_child_count = child_count
end

---@param prompt string?
function Tree:sync_prompt(prompt)
  prompt = prompt or ""
  if prompt ~= self.search_prompt then
    self.search_prompt = prompt
    self.search_collapsed = {}
  end
end

---@param prompt string
---@return table[]
---@return integer[] match_indices
function Tree:project(prompt)
  prompt = prompt or ""
  local results = {}
  local match_indices = {}
  self:sync_prompt(prompt)

  if prompt == "" then
    local function add_expanded(parent, depth)
      for _, entry in ipairs(self.children[parent] or {}) do
        local children = self.children[entry.path] or {}
        local expanded = entry.is_dir and self.expanded[entry.path] == true and #children > 0
        set_metadata(entry, depth, expanded, entry.is_dir and #children > 0, entry.is_dir and #children or nil)
        table.insert(results, entry)
        if expanded then
          add_expanded(entry.path, depth + 1)
        end
      end
    end

    add_expanded(self.root, 0)
    return results, match_indices
  end

  local included = {}
  local path_matches = {}
  local name_matches = {}

  local function include_ancestors(path)
    while path and path ~= self.root do
      included[path] = true
      path = self.parents[path]
    end
  end

  local function include_subtree(path)
    included[path] = true
    for _, child in ipairs(self.children[path] or {}) do
      include_subtree(child.path)
    end
  end

  for path, entry in pairs(self.entries) do
    if fzy.has_match(prompt, entry.ordinal or path) then
      path_matches[path] = true
      if fzy.has_match(prompt, vim.fs.basename(path)) then
        name_matches[path] = true
      end
      include_ancestors(path)
      if entry.is_dir then
        include_subtree(path)
      end
    end
  end
  local direct_matches = next(name_matches) and name_matches or path_matches

  local function add_search_results(parent, depth)
    for _, entry in ipairs(self.children[parent] or {}) do
      if included[entry.path] then
        local has_visible_children = false
        for _, child in ipairs(self.children[entry.path] or {}) do
          if included[child.path] then
            has_visible_children = true
            break
          end
        end
        local expanded = entry.is_dir and has_visible_children and not self.search_collapsed[entry.path]
        local child_count = entry.is_dir and #(self.children[entry.path] or {}) or nil
        set_metadata(entry, depth, expanded, entry.is_dir and child_count > 0, child_count)
        table.insert(results, entry)
        if direct_matches[entry.path] then
          table.insert(match_indices, #results)
        end
        if expanded then
          add_search_results(entry.path, depth + 1)
        end
      end
    end
  end

  add_search_results(self.root, 0)

  if #match_indices > 1 then
    local prefer_names = next(name_matches) ~= nil
    local scores = {}
    for _, index in ipairs(match_indices) do
      local entry = results[index]
      local subject = prefer_names and vim.fs.basename(entry.path) or entry.ordinal or entry.path
      scores[index] = fzy.score(prompt, subject)
    end
    table.sort(match_indices, function(a, b)
      if scores[a] ~= scores[b] then
        return scores[a] > scores[b]
      end
      return a < b
    end)
  end
  return results, match_indices
end

return Tree
