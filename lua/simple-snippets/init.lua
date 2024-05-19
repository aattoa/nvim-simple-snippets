local M = {}

---@alias simple-snippets.Snippet string|fun():string

---Maps filetypes to snippet tables.
---@type table<string, table<string, simple-snippets.Snippet>>
M.snippets = {}

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

---@type fun(name: string): simple-snippets.Snippet?
local function find_snippet(name)
    return vim.tbl_get(M.snippets, current_filetype(), name) or vim.tbl_get(M.snippets, "all", name)
end

---@type fun(snippet: simple-snippets.Snippet): string?
local function snippet_body(snippet)
    if type(snippet) == "string" then
        return snippet
    elseif type(snippet) == "function" then
        return snippet()
    end
end

---@type fun(name: string, offset: integer, snippet: simple-snippets.Snippet): boolean
local function expand_snippet_before_cursor(name, offset, snippet)
    local body = snippet_body(snippet)
    if type(body) == "string" then
        erase_range_on_current_line(offset, name:len())
        set_cursor_column(offset)
        vim.snippet.expand(body)
        return true
    else
        local message = "nvim-simple-snippets: Attempted to expand invalid snippet: { %s = %s }"
        vim.notify(message:format(name, vim.inspect(snippet)), vim.log.levels.WARN)
        return false
    end
end

---@type fun(line: string): string?, integer
local function simple_word_suffix(line)
    local word, prefix = line:reverse():match("^(%a+)(.*)") ---@type string?, string?
    return word and word:reverse(), prefix and prefix:len() or 0
end

---If there is a snippet name before the cursor, expand it.
---@return boolean success Whether a snippet was expanded.
M.expand = function ()
    local cursor = vim.api.nvim_win_get_cursor(0)[2]
    local name, offset = simple_word_suffix(vim.api.nvim_get_current_line():sub(1, cursor))
    local snippet = name and find_snippet(name)
    return snippet and expand_snippet_before_cursor(assert(name), offset, snippet) or false
end

---If there is a snippet name before the cursor, expand it. Otherwise jump to the next snippet tabstop.
M.expand_or_jump = function ()
    if not M.expand() then vim.snippet.jump(1) end
end

---Display available snippets in a popup-menu, and expand the selection.
M.complete = function ()
    local snippets = vim.tbl_extend("force", M.snippets.all or {}, M.snippets[current_filetype()] or {})
    if vim.tbl_isempty(snippets) then
        vim.notify("nvim-simple-snippets: No snippets available", vim.log.levels.INFO)
    else
        local column = vim.fn.col('.')
        vim.fn.complete(column, vim.tbl_keys(snippets))
        vim.api.nvim_create_autocmd("CompleteDone", {
            callback = function ()
                local word = vim.v.completed_item.word ---@type string?
                if word and #word ~= 0 then
                    assert(expand_snippet_before_cursor(word, column - 1, snippets[word]))
                end
            end,
            buffer = vim.api.nvim_get_current_buf(),
            once   = true,
        })
    end
end

return M
