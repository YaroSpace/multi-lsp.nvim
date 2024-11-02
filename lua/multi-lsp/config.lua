---@class MultiLspConfig
---@field silent boolean supress notifications if no results from Lsp server
---@field filter { method: string } default 'all' | name of Lsp server to use
local default_config = {
	enabled_servers = { "ruby_lsp", "solargraph" },
	lsp_handlers = {
		hover = {
			enabled_servers = { "all" },
			border = "rounded",
			silent = true,
			filter = {},
		},

		location = {
			enabled_servers = { "all" },
			tagfunc = {
				sort = nil
			} ,
			filter = {},
		},

		signature = {
			enabled_servers = { "all" },
			filter = {},
			border = "rounded",
			silent = true,
			focus_mapping = "K",
		},

		diagnostics = {
			enabled_servers = { "ruby_lsp" },
			filter = {},
			float = {
				border = "rounded",
				focused = false,
				header = "",
				prefix = "",
				source = false,
				style = "minimal",
			},
			severity_sort = true,
			signs = {
				text = { "", "", "󰋼", "󰌵" },
			},
			underline = true,
			update_in_insert = false,
			virtual_text = {
				source = false,
			},
		},
	},
}

return default_config
