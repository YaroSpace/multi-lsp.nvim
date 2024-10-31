local protocol = require("vim.lsp.protocol")
local _config = require("multi-lsp.config")

local M = {}

---@type table<integer, integer>
local _client_push_namespaces = {}

---@type table<string, integer>
local _client_pull_namespaces = {}

local DEFAULT_CLIENT_ID = -1

local function get_client_id(client_id)
	if client_id == nil then
		client_id = DEFAULT_CLIENT_ID
	end

	return client_id
end

---@param severity lsp.DiagnosticSeverity
local function severity_lsp_to_vim(severity)
	if type(severity) == "string" then
		severity = protocol.DiagnosticSeverity[severity] --- @type integer
	end
	return severity
end

local function convert_severity(opt)
	if type(opt) == "table" and not opt.severity and opt.severity_limit then
		vim.deprecate("severity_limit", "{min = severity} See vim.diagnostic.severity", "0.11")
		opt.severity = { min = severity_lsp_to_vim(opt.severity_limit) }
	end
end

---@param lines string[]?
---@param lnum integer
---@param col integer
---@param offset_encoding string
---@return integer
local function line_byte_from_position(lines, lnum, col, offset_encoding)
	if not lines or offset_encoding == "utf-8" then
		return col
	end

	local line = lines[lnum + 1]
	local ok, result = pcall(vim.str_byteindex, line, col, offset_encoding == "utf-16")
	if ok then
		return result --- @type integer
	end

	return col
end

---@param bufnr integer
---@return string[]?
local function get_buf_lines(bufnr)
	if vim.api.nvim_buf_is_loaded(bufnr) then
		return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	local f = io.open(filename)
	if not f then
		return
	end

	local content = f:read("*a")
	if not content then
		-- Some LSP servers report diagnostics at a directory level, in which case
		-- io.read() returns nil
		f:close()
		return
	end

	local lines = vim.split(content, "\n")
	f:close()
	return lines
end

--- @param diagnostic lsp.Diagnostic
--- @param client_id integer
--- @return table?
local function tags_lsp_to_vim(diagnostic, client_id)
	local tags ---@type table?
	for _, tag in ipairs(diagnostic.tags or {}) do
		if tag == protocol.DiagnosticTag.Unnecessary then
			tags = tags or {}
			tags.unnecessary = true
		elseif tag == protocol.DiagnosticTag.Deprecated then
			tags = tags or {}
			tags.deprecated = true
		else
			vim.lsp.log.info(string.format("Unknown DiagnosticTag %d from LSP client %d", tag, client_id))
		end
	end
	return tags
end

---@param diagnostics lsp.Diagnostic[]
---@param bufnr integer
---@param client_id integer
---@return vim.Diagnostic[]
local function diagnostic_lsp_to_vim(diagnostics, bufnr, client_id)
	local buf_lines = get_buf_lines(bufnr)
	local client = vim.lsp.get_client_by_id(client_id)
	local offset_encoding = client and client.offset_encoding or "utf-16"
	--- @param diagnostic lsp.Diagnostic
	--- @return vim.Diagnostic
	return vim.tbl_map(function(diagnostic)
		local start = diagnostic.range.start
		local _end = diagnostic.range["end"]
		--- @type vim.Diagnostic
		return {
			lnum = start.line,
			col = line_byte_from_position(buf_lines, start.line, start.character, offset_encoding),
			end_lnum = _end.line,
			end_col = line_byte_from_position(buf_lines, _end.line, _end.character, offset_encoding),
			severity = severity_lsp_to_vim(diagnostic.severity),
			message = diagnostic.message,
			source = diagnostic.source,
			code = diagnostic.code,
			_tags = tags_lsp_to_vim(diagnostic, client_id),
			user_data = {
				lsp = {
					-- usage of user_data.lsp.code is deprecated in favor of the top-level code field
					code = diagnostic.code,
					codeDescription = diagnostic.codeDescription,
					relatedInformation = diagnostic.relatedInformation,
					data = diagnostic.data,
				},
			},
		}
	end, diagnostics)
end

---@param client_id integer The id of the LSP client
---@param is_pull boolean? Whether the namespace is for a pull or push client. Defaults to push
function M.get_namespace(client_id, is_pull)
	vim.validate({ client_id = { client_id, "n" } })

	local client = vim.lsp.get_client_by_id(client_id)
	if is_pull then
		local server_id = vim.tbl_get((client or {}).server_capabilities, "diagnosticProvider", "identifier")
		local key = string.format("%d:%s", client_id, server_id or "nil")
		local name =
			string.format("vim.lsp.%s.%d.%s", client and client.name or "unknown", client_id, server_id or "nil")
		local ns = _client_pull_namespaces[key]
		if not ns then
			ns = vim.api.nvim_create_namespace(name)
			_client_pull_namespaces[key] = ns
		end
		return ns
	else
		local name = string.format("vim.lsp.%s.%d", client and client.name or "unknown", client_id)
		local ns = _client_push_namespaces[client_id]
		if not ns then
			ns = vim.api.nvim_create_namespace(name)
			_client_push_namespaces[client_id] = ns
		end
		return ns
	end
end

--- @param uri string
--- @param client_id? integer
--- @param diagnostics vim.Diagnostic[]
--- @param is_pull boolean
--- @param config? vim.diagnostic.Opts
local function handle_diagnostics(uri, client_id, diagnostics, is_pull, config)
	local fname = vim.uri_to_fname(uri)

	if #diagnostics == 0 and vim.fn.bufexists(fname) == 0 then
		return
	end

	local bufnr = vim.fn.bufadd(fname)
	if not bufnr then
		return
	end

	client_id = get_client_id(client_id)
	local namespace = M.get_namespace(client_id, is_pull)

	if config then
		--- @cast config table<string, table>
		for _, opt in pairs(config) do
			convert_severity(opt)
		end
		-- Persist configuration to ensure buffer reloads use the same
		-- configuration. To make lsp.with configuration work (See :help
		-- lsp-handler-configuration)
		vim.diagnostic.config(config, namespace)
	end

	local client = vim.lsp.get_client_by_id(client_id)
	LOG(client.name, "===============================")

	for i, diag in ipairs(diagnostics) do
		LOG(client.name, i, diag.source, diag.code, diag.message)
		if diag.data then
			for i, a in ipairs(diag.data.code_actions) do
				LOG(a.kind, a.title)
			end
		end
	end

	vim.diagnostic.set(namespace, bufnr, diagnostic_lsp_to_vim(diagnostics, bufnr, client_id))
end

---@param _ string|lsp.ResponseError?
---@param result lsp.DocumentDiagnosticReport
---@param ctx lsp.HandlerContext
---@param config vim.diagnostic.Opts Configuration table (see |vim.diagnostic.config()|).
function M.on_diagnostic(_, result, ctx, config)
	if _ == 'publishDiagnostics' then return M.on_publish_diagnostics end

LOG('diagnostic')
	if result == nil or result.kind == "unchanged" then
		return
	end

	local client = vim.lsp.get_client_by_id(ctx.client_id)
	-- LOG('on_diag', client.name, result)
	handle_diagnostics(ctx.params.textDocument.uri, ctx.client_id, result.items, true, config)
end

---@param _ lsp.ResponseError?
---@param result lsp.PublishDiagnosticsParams
---@param ctx lsp.HandlerContext
---@param config? vim.diagnostic.Opts Configuration table (see |vim.diagnostic.config()|).
function M.on_publish_diagnostics(_, result, ctx, config)
LOG('publish')
	local client = vim.lsp.get_client_by_id(ctx.client_id)
	-- LOG('publish', client.name, result)
	handle_diagnostics(result.uri, ctx.client_id, result.diagnostics, false, config)
end

return M
