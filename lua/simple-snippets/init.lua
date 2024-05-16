local M = {}

---@alias simple-snippets.Snippet string|fun():string

---Maps filetypes to snippet tables.
---@type table<string, table<string, simple-snippets.Snippet>>
M.snippets = {}

---@type fun(str: string, from: integer, to: integer): string
local function string_erase(str, from, to)
    return str:sub(1, from) .. str:sub(to + 1, -1)
end

---@type fun(offset: integer, length: integer): nil
local function erase_range_on_current_line(offset, length)
    vim.api.nvim_set_current_line(string_erase(vim.api.nvim_get_current_line(), offset, offset + length))
end

---@type fun(column: integer): nil
local function set_cursor_column(column)
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], column })
end

---@type fun(filetype: string, name: string): simple-snippets.Snippet?
local function find_snippet(filetype, name)
    return vim.tbl_get(M.snippets, filetype, name)
end

---@type fun(snippet: simple-snippets.Snippet): string?
local function snippet_body(snippet)
    if type(snippet) == "string" then
        return snippet
    elseif type(snippet) == "function" then
        return snippet()
    end
end

---@type fun(name: string, offset: integer): boolean
local function expand_snippet_before_cursor(name, offset)
    local snippet = find_snippet(vim.bo.filetype, name) or find_snippet("all", name)
    if not snippet then return false end
    erase_range_on_current_line(offset, name:len())
    set_cursor_column(offset)
    vim.snippet.expand(assert(snippet_body(snippet)))
    return true
end

---@type fun(line: string): string?, integer
local function simple_word_suffix(line)
    local word, prefix = line:reverse():match("^(%a+)(.*)") ---@type string?, string?
    return word and word:reverse(), prefix and prefix:len() or 0
end

---If there is a snippet name before the cursor, expand it.
---@return boolean success Whether a snippet was expanded.
M.expand = function ()
    local line = vim.api.nvim_get_current_line()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local name, offset = simple_word_suffix(line:sub(1, cursor[2]))
    return name and expand_snippet_before_cursor(name, offset) or false
end

---If there is a snippet name before the cursor, expand it. Otherwise jump to the next snippet tabstop.
M.expand_or_jump = function ()
    if not M.expand() then vim.snippet.jump(1) end
end

---Display available snippets in a popup-menu, and expand the selection.
M.complete = function ()
    local snippets = vim.tbl_extend("force", M.snippets.all or {}, M.snippets[vim.bo.filetype] or {})
    local column = vim.fn.col(".")
    vim.fn.complete(column, vim.tbl_keys(snippets))
    vim.api.nvim_create_autocmd("CompleteDone", {
        callback = function ()
            local word = vim.v.completed_item.word ---@type string?
            if word and #word ~= 0 then
                assert(expand_snippet_before_cursor(word, column - 1))
            end
        end,
        buffer = vim.api.nvim_get_current_buf(),
        once   = true,
    })
end

return M
