local log = require('vim.lsp.log')
local util = require("vim.lsp.util")
local protocol = require('vim.lsp.protocol')

local M = {}
---
---@class MultiLspConfig
---@field silent boolean supress notifications if no results from Lsp server
---@field filter { method: string } default 'all' | name of Lsp server to use
M.config = {
	border = "rounded",
	silent = true,
	filter = {
    ['textDocument/hover'] = 'all',
    ['textDocument/definition'] = 'all',
    ['textDocument/signatureHelp'] = 'all'
	},
	focus_signature_mapping = 'K'
}

---@param ctx lsp.HandlerContext
---@param method string LspMethod
---@return integer buf 
---@return vim.lsp.Client|nil client
---@return integer clients_no
---@return integer visits_count
local function get_context(ctx, method)
  local buf = vim.fn.bufnr()
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  local clients_no = vim.tbl_count(vim.lsp.get_clients({ bufnr = buf, method = method }))

  local visits_count = vim.F.npcall(vim.api.nvim_buf_get_var, buf, method .. '_visits_count')
  visits_count = visits_count and (visits_count + 1) or 1
  vim.api.nvim_buf_set_var(buf, method .. '_visits_count', visits_count)

  return buf, client, clients_no, visits_count
end

local function clear_context(buf, method)
  vim.api.nvim_buf_del_var(buf, method .. '_visits_count')
  vim.api.nvim_buf_del_var(buf, method .. '_result')
end

---@param _ lsp.ResponseError?
---@param result lsp.Hover
---@param ctx lsp.HandlerContext
---@param config table Configuration table.
function M.hover(_, result, ctx, config)
  local method = 'textDocument/hover'
  local buf, client, clients_no, visits_count = get_context(ctx, method)

  local filter = M.config.filter[method]
  if filter and filter ~= 'all' and filter ~= client.name then return end

	local format = "markdown"
	local contents ---@type string[]
  local stored_contents = vim.F.npcall(vim.api.nvim_buf_get_var, buf, method .. '_result')

	config = vim.tbl_deep_extend("keep", config or {}, M.config)
	config.focus_id = ctx.method

  local function show_hover_float()
	  if not stored_contents or #stored_contents == 0 or visits_count < clients_no then return end
    clear_context(buf, method)
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
--- Jumps to a location. Used as a handler for multiple LSP methods.
---@param _ nil not used
---@param result (table) result of LSP method; a location or a list of locations.
---@param ctx (lsp.HandlerContext) table containing the context of the request, including the method
---@param config? vim.lsp.LocationOpts
---(`textDocument/definition` can return `Location` or `Location[]`
M.location = function(_, result, ctx, config)
  local method = 'textDocument/definition'
  local buf, client, clients_no, visits_count = get_context(ctx, method)

  local filter = M.config.filter[method]
  if filter and filter ~= 'all' and filter ~= client.name then return end

  local stored_result = vim.F.npcall(vim.api.nvim_buf_get_var, buf, method .. '_result')
	config = vim.tbl_deep_extend("keep", config or {}, M.config)

  local function process_locations()
    if not stored_result or #stored_result == 0 or visits_count < clients_no then return end
    clear_context(buf, method)

    stored_result = remove_duplicate_locations(stored_result)

    local title = 'LSP locations'
    local items = util.locations_to_items(stored_result, client.offset_encoding)

    if config.on_list then
      assert(vim.is_callable(config.on_list), 'on_list is not a function')
      return config.on_list({ title = title, items = items })
    end

    if #stored_result == 1 then
      return util.jump_to_location(result[1], client.offset_encoding, config.reuse_win)
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

  stored_result = stored_result and vim.list_extend(stored_result, result) or result
  vim.api.nvim_buf_set_var(buf, method .. '_result', stored_result)

  process_locations()
end

local function set_mapping_for_signature_window(current_buf, signature_buf, signature_win)
  vim.keymap.set('i', M.config.focus_signature_mapping, '', {
    buffer = current_buf,
    callback = function()
      vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer = signature_buf,
        once = true,
        callback = function()
          vim.keymap.del('i', M.config.focus_signature_mapping, { buffer = current_buf })
        end
      })
      vim.api.nvim_set_current_win(signature_win)
      vim.api.nvim_input('<ESC>')
    end
  })
end

---@param _ lsp.ResponseError?
---@param result lsp.SignatureHelp  Response from the language server
---@param ctx lsp.HandlerContext Client context
---@param config table Configuration table.
---     - border:     (default=nil)
function M.signature_help(_, result, ctx, config)
  local method = 'textDocument/signatureHelp'
  local buf, client, clients_no, visits_count = get_context(ctx, method)

  local filter = M.config.filter[method]
  if filter and filter ~= 'all' and filter ~= client.name then return end

	local lines, hl
  local stored_result = vim.F.npcall(vim.api.nvim_buf_get_var, buf, method .. '_result')

	config = vim.tbl_deep_extend("keep", config or {}, M.config)
	config.focus_id = ctx.method

	local function show_signature()
    if not stored_result or #stored_result == 0 or visits_count < clients_no then return end
    clear_context(buf, method)

    local fbuf, fwin = util.open_floating_preview(stored_result, 'markdown', config)
    if hl then
      -- Highlight the second line if the signature is wrapped in a Markdown code block.
      local line = vim.startswith(stored_result[1], '```') and 1 or 0
      vim.api.nvim_buf_add_highlight(fbuf, -1, 'LspSignatureActiveParameter', line, unpack(hl))
    end

    set_mapping_for_signature_window(buf, fbuf, fwin)

    return fbuf, fwin
	end

  if buf ~= ctx.bufnr then return show_signature() end -- Ignore result since buffer changed. This happens for slow language servers.

  -- When use `autocmd CompleteDone <silent><buffer> lua vim.lsp.buf.signature_help()` to call signatureHelp handler
  -- If the completion item doesn't have signatures It will make noise. Change to use `print` that can use `<silent>` to ignore
  if not (result and result.signatures and result.signatures[1]) then
    if config.silent ~= true then print('No signature help available') end
    return show_signature()
  end

  local ft = vim.bo[ctx.bufnr].filetype
  local triggers = vim.tbl_get(client.server_capabilities, 'signatureHelpProvider', 'triggerCharacters')

  lines, hl = util.convert_signature_help_to_markdown_lines(result, ft, triggers)

  if not lines or vim.tbl_isempty(lines) then
    if config.silent ~= true then print('No signature help available') end
    return show_signature()
  end

	if clients_no > 1 then table.insert(lines, 1, string.format('*%s*', client.name)) end
  if stored_result then table.insert(stored_result, '---------') end

  stored_result = stored_result and vim.list_extend(stored_result, lines) or lines
  vim.api.nvim_buf_set_var(buf, method .. '_result', stored_result)

  return show_signature()
end

local DEFAULT_CLIENT_ID = -1

local function get_client_id(client_id)
  if client_id == nil then
    client_id = DEFAULT_CLIENT_ID
  end

  return client_id
end

---@param severity lsp.DiagnosticSeverity
local function severity_lsp_to_vim(severity)
  if type(severity) == 'string' then
    severity = protocol.DiagnosticSeverity[severity] --- @type integer
  end
  return severity
end

local function convert_severity(opt)
  if type(opt) == 'table' and not opt.severity and opt.severity_limit then
    vim.deprecate('severity_limit', '{min = severity} See vim.diagnostic.severity', '0.11')
    opt.severity = { min = severity_lsp_to_vim(opt.severity_limit) }
  end
end

--- @param config? vim.diagnostic.Opts
function M.publish_diagnostics(_, result, ctx, config)
  local uri, client_id, diagnostics, is_pull = result.uri, ctx.client_id, result.diagnostics, false

  local method = 'publishDiagnostics'
  local buf, client, clients_no, visits_count = get_context(ctx, method)

  local fname = vim.uri_to_fname(uri)

  if #diagnostics == 0 and vim.fn.bufexists(fname) == 0 then
    return
  end

  local bufnr = vim.fn.bufadd(fname)
  if not bufnr then
    return
  end

  local diag_1 = diagnostics[1] or {}
  local diag_2 = diagnostics[2] or {}

  if client.name == 'ruby-lsp' then LOG(diagnostics) end
  -- LOG(client.name, '1', diag_1.code, diag_1.message)
  -- LOG(client.name, '2', diag_2.code, diag_2.message)

  -- client_id = get_client_id(client_id)
  -- local namespace = M.get_namespace(client_id, is_pull)
  --
  -- if config then
  --   --- @cast config table<string, table>
  --   for _, opt in pairs(config) do
  --     convert_severity(opt)
  --   end
  --   -- Persist configuration to ensure buffer reloads use the same
  --   -- configuration. To make lsp.with configuration work (See :help
  --   -- lsp-handler-configuration)
  --   vim.diagnostic.config(config, namespace)
  -- end
  --
  -- vim.diagnostic.set(namespace, bufnr, diagnostic_lsp_to_vim(diagnostics, bufnr, client_id))
end

M.setup = function(opts)
  vim.lsp.handlers['textDocument/hover'] = M.hover
  vim.lsp.handlers['textDocument/definition'] = M.location
	vim.lsp.handlers["textDocument/signatureHelp"] = M.signature_help
	vim.lsp.handlers["textDocument/publishDiagnostics"] = M.publish_diagnostics

	-- vim.diagnostic.config({
	-- 	float = {
	-- 		source = "if_many",
	-- 	},
	-- 	severity_sort = true,
	-- 	signs = {
	-- 		text = { "", "", "󰋼", "󰌵" },
	-- 	},
	-- 	underline = true,
	-- 	update_in_insert = false,
	-- 	virtual_text = {
 --      source = 'if_many'
 --    }
	-- })
  LOG('Multi-lsp loaded')
end

M.setup()

return M
