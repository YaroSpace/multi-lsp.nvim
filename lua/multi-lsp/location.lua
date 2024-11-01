local util = require("vim.lsp.util")
local log = require('vim.lsp.log')

local _config = require('multi-lsp.config').lsp_handlers.location
local utils = require('multi-lsp.utils')

local M = {}

---@param locations table
local function remove_duplicate_locations(locations)
	if #locations == 2 then
		local uri_1 = locations[1].targetUri or locations[1].uri
		local uri_2 = locations[2].targetUri or locations[2].uri
		local start_line_1 = locations[1].range and locations[1].range.start.line or locations[1].targetRange.start.line
		local start_line_2 = locations[2].range and locations[2].range.start.line or locations[2].targetRange.start.line

		if uri_1 == uri_2 and start_line_1 == start_line_2 then
			table.remove(locations, 1)
		end
	end
	return locations
end

local function set_results_source(source, result)
  for _, ret in ipairs(result) do
    ret.source = source
  end
end

local function set_items_source(items)
  for _, item in ipairs(items) do
    item.text = item.text .. '  --  ' .. item.user_data.source
  end
end

--- Jumps to a location. Used as a handler for multiple LSP methods.
---@param _ nil not used
---@param result (table) result of LSP method; a location or a list of locations.
---@param ctx (lsp.HandlerContext) table containing the context of the request, including the method
---@param config? vim.lsp.LocationOpts
---(`textDocument/definition` can return `Location` or `Location[]`
M.on_location = function(_, result, ctx, config)
  local method = 'textDocument/definition'
  local buf, client, clients_no, visits_count = utils.get_context(ctx, method)
  if not client then return end

  local enabled_servers = _config.enabled_servers
  if not vim.tbl_contains(enabled_servers, 'all') and not vim.tbl_contains(enabled_servers, client.name) then return end

  local stored_result = vim.F.npcall(vim.api.nvim_buf_get_var, buf, method .. '_result')
	config = vim.tbl_deep_extend("keep", config or {}, _config)

  local function process_locations()
    if not stored_result or #stored_result == 0 or visits_count < clients_no then return end
    utils.clear_context(buf, method)

    stored_result = remove_duplicate_locations(stored_result)

    local title = 'LSP locations'
    local items = util.locations_to_items(stored_result, client.offset_encoding)

    set_items_source(items)

    if config.on_list then
      assert(vim.is_callable(config.on_list), 'on_list is not a function')
      return config.on_list({ title = title, items = items })
    end

    if #stored_result == 1 then
      return util.jump_to_location(stored_result[1], client.offset_encoding, config.reuse_win)
    end

    if config.loclist then
      vim.fn.setloclist(0, {}, ' ', { title = title, items = items })
      vim.cmd.lopen()
    else
      vim.fn.setqflist({}, ' ', { title = title, items = items })
      vim.cmd('botright copen')
    end
  end

  if result == nil or vim.tbl_isempty(result) then
    log.info(ctx.method, 'No location found')
    return process_locations()
  end

  if not vim.islist(result) then result = { result } end
  set_results_source(client.name, result)

  stored_result = stored_result and vim.list_extend(stored_result, result) or result
  vim.api.nvim_buf_set_var(buf, method .. '_result', stored_result)

  process_locations()
end

return M
