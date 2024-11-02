local util = require("vim.lsp.util")

local _config = require('multi-lsp.config').lsp_handlers.signature
local utils = require('multi-lsp.utils')

local M = {}

local function set_mapping_for_signature_window(current_buf, signature_buf, signature_win)
  vim.keymap.set('i', _config.focus_mapping, '', {
    buffer = current_buf,
    callback = function()
      vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer = signature_buf,
        once = true,
        callback = function()
          vim.keymap.del('i', _config.focus_mapping, { buffer = current_buf })
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
function M.on_signature(_, result, ctx, config)
  local method = 'textDocument/signatureHelp'
  local buf, client, clients_no, visits_count = utils.get_context(ctx, method)
  if not client then return end

  local enabled_servers = _config.enabled_servers
  if not vim.tbl_contains(enabled_servers, 'all') and not vim.tbl_contains(enabled_servers, client.name) then return end

	local lines, hl
  local stored_result = vim.F.npcall(vim.api.nvim_buf_get_var, buf, method .. '_result')

	config = vim.tbl_deep_extend("keep", config or {}, _config)
	config.focus_id = ctx.method

	local function show_signature()
    if not stored_result or #stored_result == 0 or visits_count < clients_no then return end
    utils.clear_context(buf, method)

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

function M.handler(...)
  M.on_signature(...)
end

return M
