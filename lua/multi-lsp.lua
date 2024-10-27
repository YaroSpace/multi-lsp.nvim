local log = require('vim.lsp.log')
local util = require("vim.lsp.util")

local M = {}

function M.hover(_, result, ctx, config)
  local buf = vim.fn.bufnr()
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  local clients_no = vim.tbl_count(vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/hover' }))

  local visits_count = vim.F.npcall(vim.api.nvim_buf_get_var, buf, 'visits_count')
  visits_count = visits_count and (visits_count + 1) or 1
  vim.api.nvim_buf_set_var(buf, 'visits_count', visits_count + 1)

  local stored_contents = vim.F.npcall(vim.api.nvim_buf_get_var, buf, 'stored_contents')

	local format = "markdown"
	local contents ---@type string[]

	config = config or {}
	config.focus_id = ctx.method

	config = vim.tbl_deep_extend("force", config, {
		border = "rounded",
		silent = true,
	})

  local function show_hover_float()
	  if visits_count < clients_no then return end

    vim.api.nvim_buf_del_var(buf, 'visits_count')
    vim.api.nvim_buf_del_var(buf, 'stored_contents')

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

	if clients_no > 1 then
		result.contents.value = '*' .. client.name .. '*' .. "\n\n" .. vim.fn.trim(result.contents.value, '\n')
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

  if  clients_no > 1 and visits_count == 1 then vim.list_extend(contents, {'---------\n'}) end
  stored_contents = stored_contents and vim.list_extend(stored_contents, contents) or contents
  vim.api.nvim_buf_set_var(buf, 'stored_contents', stored_contents)

	return show_hover_float()
end

--- Jumps to a location. Used as a handler for multiple LSP methods.
---@param _ nil not used
---@param result (table) result of LSP method; a location or a list of locations.
---@param ctx (lsp.HandlerContext) table containing the context of the request, including the method
---@param config? vim.lsp.LocationOpts
---(`textDocument/definition` can return `Location` or `Location[]`
M.location_handler = function(_, result, ctx, config)
  local buf = vim.fn.bufnr()
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  local clients_no = vim.tbl_count(vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/hover' }))

  local visits_count = vim.F.npcall(vim.api.nvim_buf_get_var, buf, 'visits_count')
  visits_count = visits_count and (visits_count + 1) or 1
  vim.api.nvim_buf_set_var(buf, 'visits_count', visits_count + 1)

  config = config or {}

  vim.print(client.name)

  if result == nil or vim.tbl_isempty(result) then
    log.info(ctx.method, 'No location found')
    return nil
  end

  if not vim.islist(result) then
    result = { result }
  end

  local title = 'LSP locations'
  local items = util.locations_to_items(result, client.offset_encoding)

  if config.on_list then
    assert(vim.is_callable(config.on_list), 'on_list is not a function')
    config.on_list({ title = title, items = items })
    return
  end
  vim.print(client.name, result)
  if #result == 1 then
    util.jump_to_location(result[1], client.offset_encoding, config.reuse_win)
    return
  end
  if config.loclist then
    vim.fn.setloclist(0, {}, ' ', { title = title, items = items })
    vim.cmd.lopen()
  else
    vim.fn.setqflist({}, ' ', { title = title, items = items })
    vim.cmd('botright copen')
  end
end

M.setup = function(opts)
  vim.lsp.handlers['textDocument/hover'] = M.hover
  vim.lsp.handlers['textDocument/definition'] = M.location_handler

  vim.keymap.set('n', ',w', ":w | =loadfile('~/projects/multi-lsp.nvim/multi-lsp.lua')()<cr>", {})
print('QQQQQQQQQQ')
end

print('Loaded')
return M
