# roslyn.nvim

A native Neovim LSP wrapper for the [Roslyn](https://github.com/dotnet/roslyn) C# language server. Built for Neovim 0.12+ using `vim.lsp.config` and `vim.lsp.enable`.

## Requirements

- Neovim >= 0.12
- Roslyn language server (install via [Mason](https://github.com/williamboman/mason.nvim) with the [Crashdummyy registry](https://github.com/Crashdummyy/mason-registry))

## Install

Add to your plugin manager. Example with `vim.pack.add`:

```lua
vim.pack.add { 'https://github.com/justinlazarus/roslyn.nvim' }
```

## Setup

```lua
require('roslyn').setup({
  -- "auto" | "off" — control file watching behavior
  filewatching = 'auto',
  -- Recursively search for solution files in monorepos
  broad_search = false,
  -- Always reuse the previously selected solution target
  lock_target = false,
  -- Load nearest project first, then upgrade to full solution (faster startup)
  fast_init = false,
})
```

That's it. The plugin registers `roslyn` as a native LSP config and calls `vim.lsp.enable('roslyn')`.

## Commands

| Command | Description |
|---|---|
| `:Roslyn info` | Show server status, target, and capabilities |
| `:Roslyn target` | Switch solution or project target |
| `:Roslyn restart` | Restart the language server |
| `:Roslyn stop` | Stop the language server |
| `:Roslyn restore` | Run dotnet restore (via LSP or shell fallback) |
| `:Roslyn log` | Open the LSP log file |
| `:Roslyn incoming_calls` | Show incoming calls to symbol under cursor |
| `:Roslyn outgoing_calls` | Show outgoing calls from symbol under cursor |
| `:Roslyn references` | Find all references to symbol under cursor |
| `:Roslyn implementation` | Go to implementation |
| `:Roslyn type_definition` | Go to type definition |
| `:Roslyn document_symbols` | List symbols in current document |
| `:Roslyn workspace_symbols [query]` | Search symbols across workspace |
| `:Roslyn organize_imports` | Organize using directives |
| `:Roslyn fix_all` | Apply fix-all code actions |
| `:Roslyn open_sourcegen <uri>` | Open a source-generated document |

## Autocmd Events

| Event | Pattern | Description |
|---|---|---|
| `User` | `RoslynInitialized` | Workspace initialization complete |
| `User` | `RoslynAttach` | Client attached to a buffer |
| `User` | `RoslynRestoreNeeded` | Server reports a project needs restore |
| `User` | `RoslynRestoreComplete` | Restore finished (shell fallback) |

## Native LSP

This plugin uses Neovim's built-in LSP client. All standard LSP features work out of the box:

- `vim.lsp.buf.definition()` / `vim.lsp.buf.references()` / `vim.lsp.buf.implementation()`
- `vim.lsp.buf.hover()` / `vim.lsp.buf.signature_help()`
- `vim.lsp.buf.code_action()` / `vim.lsp.buf.rename()`
- `vim.lsp.buf.format()`
- `vim.lsp.buf.document_symbol()` / `vim.lsp.buf.workspace_symbol()`
- Inlay hints, semantic tokens, diagnostics — all via native Neovim APIs

### Roslyn-specific extensions

- Nested code actions (Roslyn groups refactorings into sub-menus)
- Fix-all code actions with scope selection (document/project/solution)
- Organize imports (using directives)
- Call hierarchy (incoming/outgoing calls)
- Source-generated document viewing
- Solution/project switching without restart
- Full capability negotiation (semantic tokens, inlay hints, snippets, code action kinds)

### Concurrency

Roslyn uses StreamJsonRpc which handles concurrent requests natively via async dispatch.
Neovim's LSP client supports multiple in-flight requests with tracking and cancellation (`$/cancelRequest`).
No special configuration needed — concurrent request handling works out of the box.

## License

MIT
