local M = {}

---@alias simple-snippets.Snippet string|fun():string

---Maps filetypes to snippet tables.
---@type table<string, table<string, simple-snippets.Snippet>>
M.snippets = {}

---@type fun(message: string, level: integer?)
local function notify(message, level)
    vim.notify("nvim-simple-snippets: " .. message, level or vim.log.levels.INFO)
end

---@return string?
local function treesitter_language_under_cursor()
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    local range = { line, col, line - 1, col } ---@type Range4
    return vim.treesitter.get_parser():language_for_range(range):lang()
end

---@return string
local function current_filetype()
    local highlighter = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]
    return highlighter and treesitter_language_under_cursor() or vim.bo.filetype
end

---@type fun(): table<string, simple-snippets.Snippet>
local function snippets_for_current_filetype()
    return vim.tbl_extend("keep", M.snippets[current_filetype()] or {}, M.snippets.all or {})
end

---@type fun(from: integer, to: integer)
local function erase_range_on_current_line(from, to)
    local line = vim.api.nvim_get_current_line()
    vim.api.nvim_set_current_line(line:sub(1, from) .. line:sub(to + 1, -1))
end

---@param word string
local function erase_word_before_cursor(word)
    local old_cursor = vim.fn.col('.') - 1
    local new_cursor = old_cursor - #word
    erase_range_on_current_line(new_cursor, old_cursor)
    vim.api.nvim_win_set_cursor(0, { vim.fn.line('.'), new_cursor })
end

---@type fun(snippet: simple-snippets.Snippet): string?
local function snippet_body(snippet)
    if type(snippet) == "string" then
        return snippet
    elseif type(snippet) == "function" then
        return snippet_body(snippet())
    else
        notify("Attempted to expand invalid snippet: " .. vim.inspect(snippet), vim.log.levels.WARN)
    end
end

---@type fun(line: string): string?
local function simple_word_suffix(line)
    local word = line:reverse():match("^(%a+)") ---@type string?
    return word and word:reverse()
end

---@type fun(name: string): string?
local function find_snippet(name)
    local snippets = snippets_for_current_filetype()
    local snippet = snippets and snippets[name]
    return snippet and snippet_body(snippet)
end

---@param snippets table<string, simple-snippets.Snippet>
local function complete_snippets(snippets)
    vim.fn.complete(vim.fn.col('.'), vim.tbl_keys(snippets))
    vim.api.nvim_create_autocmd("CompleteDone", {
        callback = function ()
            local word = vim.v.completed_item.word ---@type string?
            local body = word and #word ~= 0 and snippet_body(snippets[word])
            if not (word and body) then return end
            erase_word_before_cursor(word)
            vim.snippet.expand(body)
        end,
        buffer = vim.api.nvim_get_current_buf(),
        once   = true,
    })
end

---If there is a snippet name before the cursor, expand it.
---@return boolean success Whether a snippet was expanded.
M.expand = function ()
    local name = simple_word_suffix(vim.api.nvim_get_current_line():sub(1, vim.fn.col('.') - 1))
    local body = name and find_snippet(name)
    if not name or not body then return false end
    erase_word_before_cursor(name)
    vim.snippet.expand(body)
    return true
end

---If there is a snippet name before the cursor, expand it. Otherwise jump to the next snippet tabstop.
M.expand_or_jump = function ()
    if not M.expand() then vim.snippet.jump(1) end
end

---Display available snippets in a popup-menu, and expand the selection.
M.complete = function ()
    local snippets = snippets_for_current_filetype()
    if vim.tbl_isempty(snippets) then
        notify("No snippets available")
    else
        complete_snippets(snippets)
    end
end

return M
