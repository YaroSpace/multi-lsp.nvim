local hover = require('multi-lsp.hover').hover
local location = require('multi-lsp.location').location
local signature = require('multi-lsp.signature').signature
local diagnostics = require('multi-lsp.diagnostics').diagnostics

local M = {}

M.setup = function(opts)
  vim.lsp.handlers['textDocument/hover'] = hover
  vim.lsp.handlers['textDocument/definition'] = location
	vim.lsp.handlers["textDocument/signatureHelp"] = signature
	-- vim.lsp.handlers["textDocument/publishDiagnostics"] = diagnostics

  LOG('Multi-lsp loaded')
end

M.setup()

return M
