local M = {}

---@param ctx lsp.HandlerContext
---@param method string LspMethod
---@return integer buf 
---@return vim.lsp.Client|nil client
---@return integer clients_no
---@return integer visits_count
M.get_context = function(ctx, method)
  local buf = vim.fn.bufnr()
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  local clients_no = vim.tbl_count(vim.lsp.get_clients({ bufnr = buf, method = method }))

  local visits_count = vim.F.npcall(vim.api.nvim_buf_get_var, buf, method .. '_visits_count')
  visits_count = visits_count and (visits_count + 1) or 1
  vim.api.nvim_buf_set_var(buf, method .. '_visits_count', visits_count)

  return buf, client, clients_no, visits_count
end

M.clear_context = function (buf, method)
  vim.api.nvim_buf_del_var(buf, method .. '_visits_count')
  vim.api.nvim_buf_del_var(buf, method .. '_result')
end

return M
