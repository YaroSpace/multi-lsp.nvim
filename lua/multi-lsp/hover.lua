local util = require("vim.lsp.util")

local _config = require('multi-lsp.config').lsp_handlers.hover
local utils = require('multi-lsp.utils')

local M = {}

---@param _ lsp.ResponseError?
---@param result lsp.Hover
---@param ctx lsp.HandlerContext
---@param config table Configuration table.
function M.on_hover(_, result, ctx, config)
  local method = 'textDocument/hover'
  local buf, client, clients_no, visits_count = utils.get_context(ctx, method)
  if not client then return end

  local enabled_servers = _config.enabled_servers
  if not vim.tbl_contains(enabled_servers, 'all') and not vim.tbl_contains(enabled_servers, client.name) then return end

	local format = "markdown"
	local contents ---@type string[]
  local stored_contents = vim.F.npcall(vim.api.nvim_buf_get_var, buf, method .. '_result')

	config = vim.tbl_deep_extend("keep", config or {}, _config)
	config.focus_id = ctx.method

  local function show_hover_float()
	  if not stored_contents or #stored_contents == 0 or visits_count < clients_no then return end
    utils.clear_context(buf, method)
		return util.open_floating_preview(stored_contents, format, config)
	end

	if buf ~= ctx.bufnr then
	  return show_hover_float()
	end
	if not (result and result.contents) then
		if config.silent ~= true then
			vim.notify("No information available")
		end
	  return show_hover_float()
	end

	if type(result.contents) == "table" and result.contents.kind == "plaintext" then
		format = "plaintext"
		contents = vim.split(result.contents.value or "", "\n", { trimempty = true })
	else
		contents = util.convert_input_to_markdown_lines(result.contents)
	end

	if vim.tbl_isempty(contents) then
		if config.silent ~= true then vim.notify("No information available") end
		return show_hover_float()
	end

	if clients_no > 1 then table.insert(contents, 1, string.format('*%s*', client.name)) end
  if stored_contents then table.insert(stored_contents, '---------') end

  stored_contents = stored_contents and vim.list_extend(stored_contents, contents) or contents
  vim.api.nvim_buf_set_var(buf, method .. '_result', stored_contents)

	return show_hover_float()
end

return M
