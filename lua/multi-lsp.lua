Redefine_require(true)

local config = require("multi-lsp.config")

local hover = require("multi-lsp.hover")
local location = require("multi-lsp.location")
local signature = require("multi-lsp.signature")
local diagnostic = require("multi-lsp.diagnostics")

local M = {}

local function is_enabled(client, method)
  local enabled_servers = config.lsp_handlers[method].enabled_servers
  return vim.tbl_contains(enabled_servers, client.name) or vim.tbl_contains(enabled_servers, 'all')
end

---Stub out filtered methods, so that Lsp does not fallback to built-in implementation
local function stub(_)
	return stub
end

---@param client vim.lsp.Client
local function setup_handlers(client)
	if not vim.tbl_contains(config.enabled_servers, client.name) then return end

  local client_handlers = {}

	local handler = is_enabled(client, 'signature') and signature.handler or stub
	client_handlers["textDocument/signatureHelp"] = handler

	handler = is_enabled(client, 'hover') and hover.handler or stub
	client_handlers["textDocument/hover"] = handler

	handler = is_enabled(client, 'location') and location.handler or stub
	client_handlers["textDocument/definition"] = handler
  client_handlers["textDocument/implementation"] = handler
  client_handlers["textDocument/typeDefinition"] = handler
  client_handlers["textDocument/declaration"] = handler

	if config.lsp_handlers.location.tagfunc then vim.lsp.tagfunc = location.tagfunc end

	handler = is_enabled(client, 'diagnostics') and diagnostic.handler or stub
	client_handlers["textDocument/diagnostic"] = handler
	client_handlers["textDocument/publishDiagnostics"] = handler('publishDiagnostics')

	client.handlers = client_handlers

	vim.notify("Multi-lsp loaded for client " .. client.name)
end

local set_lsp_attach_command = function()
  vim.api.nvim_create_autocmd("LspAttach", {
  	desc = 'Multi-lsp handlers setup',
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client then setup_handlers(client) end
    end,
  })
end

---@param opts table
M.setup = function(opts)
  config = vim.tbl_extend('force', opts, config)
  set_lsp_attach_command()
end

for _, client in ipairs(vim.lsp.get_clients()) do
	setup_handlers(client)
end

Redefine_require()

return M
