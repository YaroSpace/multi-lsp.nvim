local _config = require("multi-lsp.config").lsp_handlers.diagnostics

local M = {}

---@param _ string|lsp.ResponseError?
---@param result lsp.DocumentDiagnosticReport
---@param ctx lsp.HandlerContext
---@param config vim.diagnostic.Opts Configuration table (see |vim.diagnostic.config()|).
function M.on_diagnostic(_, result, ctx, config)
	if _ == 'publishDiagnostics' then return M.on_publish_diagnostics end

  config = vim.tbl_extend('keep', config or {}, _config)
  local ns = vim.lsp.diagnostic.get_namespace(ctx.client_id)
  vim.diagnostic.config(config) -- passing config for the namespace doe not have effect for some reason

  ---@cast _ lsp.ResponseError
  return vim.lsp.diagnostic.on_diagnostic(_, result, ctx, config)
end

---@param _ lsp.ResponseError?
---@param result lsp.PublishDiagnosticsParams
---@param ctx lsp.HandlerContext
---@param config? vim.diagnostic.Opts Configuration table (see |vim.diagnostic.config()|).
function M.on_publish_diagnostics(_, result, ctx, config)
  config = vim.tbl_extend('keep', config or {}, _config)
  local ns = vim.lsp.diagnostic.get_namespace(ctx.client_id)
  vim.diagnostic.config(config)

  return vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx, config)
end

return M
