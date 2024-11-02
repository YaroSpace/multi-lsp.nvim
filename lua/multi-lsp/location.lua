local util = require("vim.lsp.util")
local log = require('vim.lsp.log')

local _config = require('multi-lsp.config').lsp_handlers.location
local utils = require('multi-lsp.utils')

local M = {}

---@param locations table
local function remove_duplicate_locations(locations)
  local ret = {}
  local uniq = {}

  for _, el in ipairs(locations) do
    local key = el.filename .. el.lnum
    if not uniq[key] then
      uniq[key] = el
      table.insert(ret, el)
    end
  end

	return ret
end

local function sort_locations(el_1, el_2)
  local filename = vim.fn.bufname()

  if el_1.filename == el_2.filename then
    return el_1.lnum < el_2.lnum
  end

  local score_1 = el_1.filename:find(filename) and 100 or 0
  local score_2 = el_2.filename:find(filename) and 100 or 0

  if score_1 ~= score_2 then return score_1 > score_2 end

  local score_1 = el_1.filename:find('%.rbs') and 100 or 0
  local score_2 = el_2.filename:find('%.rbs') and 100 or 0

  if score_1 ~= score_2 then return score_1 < score_2 end

  return el_1.filename < el_2.filename
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

    local title = 'LSP locations'

    local items = util.locations_to_items(stored_result, client.offset_encoding)

    items = remove_duplicate_locations(items)
    table.sort(items, _config.tagfunc.sort or sort_locations)

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

function M.handler(...)
  M.on_location(...)
end

M.tagfunc = function(pattern, flags)
  flags = 'c'
  local ret = vim.lsp._tagfunc(pattern, flags)

  if ret == vim.NIL then return end

  for i, el in ipairs(ret) do
    ret[i].lnum = el.cmd:find('%%(%d+)l')
  end
  table.sort(ret, sort_locations)

  return ret
end

return M
