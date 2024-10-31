---@class MultiLspConfig
---@field silent boolean supress notifications if no results from Lsp server
---@field filter { method: string } default 'all' | name of Lsp server to use
local config = {
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
			enabled_servers = { "all" },
			filter = {},
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
		},
	},
}

return config
