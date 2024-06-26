local M = {}

M.configuration = {}

---@alias simple-snippets.Snippet string|fun():string
---@alias simple-snippets.SnippetTable table<string, table<string, simple-snippets.Snippet>>

---Maps filetypes to snippet tables.
---@type simple-snippets.SnippetTable
M.snippets = {}

---@type fun(message: string, level: integer?)
local function notify(message, level)
    vim.notify('nvim-simple-snippets: ' .. message, level or vim.log.levels.INFO)
end

---@return string[]?
local function treesitter_filetypes_under_cursor()
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    local range = { line, col, line - 1, col } ---@type Range4
    local language = vim.treesitter.get_parser():language_for_range(range):lang()
    return language and vim.treesitter.language.get_filetypes(language)
end

---@return boolean
local function use_treesitter()
    return M.configuration.treesitter and vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil
end

---@return string[]
local function current_filetypes()
    local filetypes = use_treesitter() and treesitter_filetypes_under_cursor() or {}
    if not vim.list_contains(filetypes, vim.bo.filetype) then
        table.insert(filetypes, vim.bo.filetype)
    end
    table.insert(filetypes, 'all')
    return filetypes
end

---@type fun(filetype: string): table<string, simple-snippets.Snippet>
local function snippets_for_filetype(filetype)
    return M.snippets[filetype] or {}
end

---@type fun(): table<string, simple-snippets.Snippet>
local function snippets_for_cursor()
    local snippet_tables = vim.iter(current_filetypes()):map(snippets_for_filetype):totable()
    return vim.tbl_extend('keep', unpack(snippet_tables))
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
    if type(snippet) == 'string' then
        return snippet
    elseif type(snippet) == 'function' then
        return snippet_body(snippet())
    else
        notify('Attempted to expand invalid snippet: ' .. vim.inspect(snippet), vim.log.levels.WARN)
    end
end

---@type fun(name: string): string?
local function find_snippet(name)
    local snippets = snippets_for_cursor()
    local snippet = snippets and snippets[name]
    return snippet and snippet_body(snippet)
end

---@return string? word
local function word_before_cursor()
    return vim.api.nvim_get_current_line():sub(1, vim.fn.col('.') - 1):match('%a+$')
end

---@return boolean success Whether a snippet was expanded.
M.expand = function ()
    local name = word_before_cursor()
    local body = name and find_snippet(name)
    if not (name and body) then return false end
    erase_word_before_cursor(name)
    vim.snippet.expand(body)
    return true
end

M.expand_or_jump = function ()
    if not M.expand() then vim.snippet.jump(1) end
end

-- LSP completion specification:
-- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_completion

local lsp_snippet_insertTextFormat = 2

---@type fun(name: string, snippet: simple-snippets.Snippet): table
local function make_completion_item(name, snippet)
    local body = snippet_body(snippet)
    if not body then
        return {
            word = name,
            menu = '(invalid)',
            info = 'This snippet has an invalid body!',
        }
    end
    ---@type lsp.CompletionItem
    local item = {
        label            = name,
        insertText       = body,
        insertTextFormat = lsp_snippet_insertTextFormat,
    }
    return {
        word      = name,
        info      = body,
        user_data = { ['nvim-simple-snippets'] = { completion_item = item } },
    }
end

---@return lsp.CompletionItem?
local function completion_item_userdata()
    return vim.tbl_get(vim.v.completed_item, 'user_data', 'nvim', 'lsp', 'completion_item')
        or vim.tbl_get(vim.v.completed_item, 'user_data', 'nvim-simple-snippets', 'completion_item')
end

---@type fun(item: lsp.CompletionItem, buffer: integer)
local function apply_completion(item, buffer)
    if item.additionalTextEdits then
        vim.lsp.util.apply_text_edits(item.additionalTextEdits, buffer, vim.opt.encoding:get())
    end
    vim.snippet.expand(vim.tbl_get(item, 'textEdit', 'newText') or item.insertText or vim.v.completed_item.word)
end

local function expand_completed_snippet()
    local item = completion_item_userdata()
    if item and item.insertTextFormat == lsp_snippet_insertTextFormat then
        erase_word_before_cursor(vim.v.completed_item.word)
        apply_completion(item, vim.api.nvim_get_current_buf())
        vim.v.completed_item = vim.empty_dict() -- Sometimes not cleared automatically for some reason.
    end
end

---@return integer
local function completion_autogroup()
    return vim.api.nvim_create_augroup('nvim-simple-snippets-expand-completion', { clear = true })
end

M.enable_expand_completed_snippets = function ()
    vim.api.nvim_create_autocmd('CompleteDone', {
        callback = expand_completed_snippet,
        group    = completion_autogroup(),
        desc     = 'Expand completed snippets',
    })
end

M.disable_expand_completed_snippets = function ()
    completion_autogroup()
end

M.complete = function ()
    local snippets = snippets_for_cursor()
    if vim.tbl_isempty(snippets) then
        notify('No snippets available')
    else
        vim.fn.complete(vim.fn.col('.'), vim.iter(pairs(snippets)):map(make_completion_item):totable())
    end
end

---@param snippets simple-snippets.SnippetTable Snippets to be merged with the global snippet table.
M.add = function (snippets)
    M.snippets = vim.tbl_deep_extend('force', M.snippets, snippets)
end

---@class simple-snippets.SetupOptions
---@field completion boolean Whether to expand completed snippets.
---@field treesitter boolean Whether to use treesitter for filetype detection.
---@field snippets simple-snippets.SnippetTable

---@param options simple-snippets.SetupOptions?
M.setup = function (options)
    options = options or {}
    if options.completion then
        M.enable_expand_completed_snippets()
    end
    if options.snippets then
        M.add(options.snippets)
    end
    M.configuration.treesitter = options.treesitter
end

return M
