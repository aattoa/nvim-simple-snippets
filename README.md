# nvim-simple-snippets

A tiny snippet management plugin for neovim.

The plugin relies on neovim's built in Lua module `vim.snippet`, so `nvim >= 0.10` is required.

## Features

- Define your own snippets.
- Expand custom snippets by using the word before the cursor as a trigger.
- Expand snippet completions, such as those provided by language servers.

## Optional setup

```lua
require('simple-snippets').setup(options)
```

The `options` table may contain the following keys:

- completion: boolean (default false), whether to expand completed snippets.
- treesitter: boolean (default false), whether to use treesitter for filetype detection.
- snippets: `simple-snippets.SnippetTable` (default empty), snippets to be merged with the global snippet table.

Example plugin spec for [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'aattoa/nvim-simple-snippets',
    opts = {
        completion = true,
        treesitter = true,
        snippets = your_snippet_table, -- See the snippet table section.
    },
    keys = {
        -- Lazy-load the plugin when one of following key mappings is used ...
        { '<C-l>', function () require('simple-snippets').expand_or_jump() end, mode = 'i' },
        { '<C-s>', function () require('simple-snippets').complete()       end, mode = 'i' },
    },
    -- ... Or when an LSP client is attached to a buffer.
    event = 'LspAttach',
    -- Make sure lazy-loading is enabled.
    lazy = true,
    -- Only enable the plugin if `vim.snippet` exists.
    enabled = vim.snippet ~= nil,
}
```

In order to effectively jump between snippet tabstops, separate mappings are required, such as the following:

```lua
vim.keymap.set({ 'i', 's' }, '<C-h>', function () vim.snippet.jump(-1) end)
vim.keymap.set('s',          '<C-l>', function () vim.snippet.jump(1) end)
```

## LSP snippet completion items

Neovim's default LSP client capabilities do not include snippet support, so language servers won't attempt to provide snippet completion items.

You can fix this by merging the following table with your existing LSP client capabilities:

```lua
local snippet_capabilities = { textDocument = { completion = { completionItem = { snippetSupport = true } } } }
```

For example, if you use [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig), you can pass the following capabilities to each client's setup function:

```lua
local capabilities = vim.tbl_deep_extend('force', vim.lsp.protocol.make_client_capabilities(), snippet_capabilities)
```

## Type `simple-snippets.Snippet`

A snippet is represented either as a string or a function that returns a string: `string|fun():string`

For snippet syntax, see the [LSP snippet specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#snippet_syntax).

## Type `simple-snippets.SnippetTable`

A snippet table maps filetypes to snippet definition tables: `table<string, table<string, simple-snippets.Snippet>>`

The following example snippet table defines a `main` snippet for python and a `time` snippet for all filetypes, which will expand to the current time at the time of expansion.

```lua
{
    python = {
        main = 'if __name__ == "__main__":\n\t${1:pass}',
    },
    all = {
        time = function () return os.date('%T') end,
    },
}
```

## API

The plugin provides the following interface, accessible through `require('simple-snippets')`:

- snippets: `simple-snippets.SnippetTable`

    The global snippet table.

- expand: `fun(): boolean`

    If there is a snippet name before the cursor, expand it.

- expand_or_jump: `fun(): nil`

    Same as the above, but if no snippet was expanded, jump to the next snippet tabstop.

- enable_expand_completed_snippets: `fun(): nil`

    Enable the expansion of completed snippets, such as those provided by language servers, or this plugin's `complete` function.

- disable_expand_completed_snippets: `fun(): nil`

    Opposite of the above.

- complete: `fun(): nil`

    Display available snippets in a popup-menu, and expand the selection. Expansion of completed snippets must be enabled for this to work!

- add: `fun(snippets: simple-snippets.SnippetTable): nil`

    Marge `snippets` with the global snippet table.
