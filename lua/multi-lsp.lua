package.loaded['multi-lsp.hover'] = nil
package.loaded['multi-lsp.location'] = nil
package.loaded['multi-lsp.signature'] = nil
package.loaded['multi-lsp.diagnostics'] = nil
package.loaded['multi-lsp.config'] = nil

local config = require("multi-lsp.config")

local on_hover = require("multi-lsp.hover").on_hover
local on_location = require("multi-lsp.location").on_location
local on_signature = require("multi-lsp.signature").on_signature
local diagnostics = require("multi-lsp.diagnostics")

local M = {}

local function is_enabled(client, method)
  local enabled_servers = config.lsp_handlers[method].enabled_servers
  return vim.tbl_contains(enabled_servers, client.name) or vim.tbl_contains(enabled_servers, 'all')
end

---@param client vim.lsp.Client
local function setup_handlers(client)
	if not vim.tbl_contains(config.enabled_servers, client.name) then return end

	local client_handlers = client.handlers

	if is_enabled(client, 'signature') then
	  client_handlers["textDocument/signatureHelp"] = on_signature
	end

	if is_enabled(client, 'hover') then
		client_handlers["textDocument/hover"] = on_hover
	end

	if is_enabled(client, 'location') then
	  client_handlers["textDocument/definition"] = on_location
    client_handlers["textDocument/implementation"] = on_location
    client_handlers["textDocument/typeDefinition"] = on_location
    client_handlers["textDocument/declaration"] = on_location
	end

	if is_enabled(client, 'diagnostics') then
		client_handlers["textDocument/publishDiagnostics"] = diagnostics.on_publish_diagnostics
		client_handlers["textDocument/diagnostics"] = diagnostics.on_diagnostic
	end

	LOG("Multi-lsp loaded for client " .. client.name)
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

return M
