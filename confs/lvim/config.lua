-- vim options
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.relativenumber = true

lvim.log.level = "info"
lvim.format_on_save = {
	enabled = true,
	pattern = "*",
	timeout = 1000,
}
-- keymappings <https://www.lunarvim.org/docs/configuration/keybindings>
-- add your own keymapping
lvim.keys.normal_mode["<C-s>"] = ":w<cr>"

lvim.keys.normal_mode["<S-l>"] = ":BufferLineCycleNext<CR>"
lvim.keys.normal_mode["<S-h>"] = ":BufferLineCyclePrev<CR>"

-- -- Use which-key to add extra bindings with the leader-key prefix
-- lvim.builtin.which_key.mappings["W"] = { "<cmd>noautocmd w<cr>", "Save without formatting" }
-- lvim.builtin.which_key.mappings["P"] = { "<cmd>Telescope projects<CR>", "Projects" }

lvim.colorscheme = "gruvbox"

lvim.builtin.alpha.active = true
lvim.builtin.alpha.mode = "dashboard"
lvim.builtin.terminal.active = true
lvim.builtin.nvimtree.setup.view.side = "left"
lvim.builtin.nvimtree.setup.renderer.icons.show.git = false

lvim.builtin.treesitter.auto_install = true

lvim.builtin.treesitter.ensure_installed = { "comment", "markdown_inline", "regex" }

-- -- genericLSP settings <https://www.lunarvim.org/docs/languages#lsp-support>

-- --- disable automatic installation of servers
lvim.lsp.installer.setup.automatic_installation = true

-- ---configure a server manually. IMPORTANT: Requires `:LvimCacheReset` to take effect
-- ---see the full default list `:lua =lvim.lsp.automatic_configuration.skipped_servers`
-- vim.list_extend(lvim.lsp.automatic_configuration.skipped_servers, { "pyright" })
-- local opts = {} -- check the lspconfig documentation for a list of all possible options
-- require("lvim.lsp.manager").setup("pyright", opts)

-- -- you can set a custom on_attach function that will be used for all the language servers
-- -- See <https://github.com/neovim/nvim-lspconfig#keybindings-and-completion>
-- lvim.lsp.on_attach_callback = function(client, bufnr)
--   local function buf_set_option(...)
--     vim.api.nvim_buf_set_option(bufnr, ...)
--   end
--   --Enable completion triggered by <c-x><c-o>
--   buf_set_option("omnifunc", "v:lua.vim.lsp.omnifunc")
-- end

-- -- linters and formatters <https://www.lunarvim.org/docs/languages#lintingformatting>
local formatters = require("lvim.lsp.null-ls.formatters")
formatters.setup({
	{ command = "stylua" },
})
local linters = require("lvim.lsp.null-ls.linters")
linters.setup({
	{ command = "flake8", filetypes = { "python" } },
	{
		command = "shellcheck",
		args = { "--severity", "warning" },
	},
})

-- -- Additional Plugins <https://www.lunarvim.org/docs/plugins#user-plugins>
lvim.plugins = {
	{
		"jamessan/vim-gnupg",
	},
	{
		"lervag/vimtex",
		lazy = false,
		ft = { "tex", "latex", "bib" },
		config = function()
			-- require "plugins.vimtex"
			vim.cmd([[
      call vimtex#init()
      let g:vimtex_view_method = 'zathura'
      ]])
		end,
		init = function()
			vim.cmd([[
      let g:vimtex_view_method = 'zathura'
      ]])
		end,
	},
	{
		"David-Kunz/gen.nvim",
		opts = {
			model = "starcoder2:15b",
			display_mode = "float",
			show_prompt = false,
			show_model = true,
			no_auto_close = false,
			init = function(options)
				pcall(io.popen, "ollama serve > /dev/null 2>&1 &")
			end,
			-- Function to initialize Ollama
			command = function(options)
				return "curl --silent --no-buffer -X POST http://"
					.. options.host
					.. ":"
					.. options.port
					.. "/api/generate -d $body"
			end,
			debug = false,
		},
	},
	{
		"huggingface/llm.nvim",
		opts = {
			backend = "ollama",
			model = "gemma:instruct",
			accept_keymap = "<S-CR>",
			dismiss_keymap = "<CR>",
			url = "http://localhost:11434/api/generate",
			request_body = {
				options = {
					temperature = 0.2,
					top_p = 0.95,
				},
			},
			enable_suggestions_on_startup = true,
			lsp = {
				bin_path = vim.api.nvim_call_function("stdpath", { "data" }) .. "/mason/bin/llm-ls",
			},
		},
	},

	--   {
	--     "zbirenbaum/copilot.lua",
	--     cmd = "Copilot",
	--     event = "InsertEnter",
	--     config = function()
	-- require('copilot').setup({
	--   panel = {
	--     enabled = true,
	--     auto_refresh = false,
	--     keymap = {
	--       jump_prev = "[[",
	--       jump_next = "]]",
	--       accept = "<CR>",
	--       refresh = "gr",
	--       open = "<M-CR>"
	--     },
	--     layout = {
	--       position = "bottom", -- | top | left | right
	--       ratio = 0.4
	--     },
	--   },
	--   suggestion = {
	--     enabled = true,
	--     auto_trigger = true,
	--     debounce = 75,
	--     keymap = {
	--       accept = "<M-l>",
	--       accept_word = false,
	--       accept_line = false,
	--       next = "<M-]>",
	--       prev = "<M-[>",
	--       dismiss = "<C-]>",
	--     },
	--   },
	--   filetypes = {
	--     yaml = false,
	--     markdown = false,
	--     help = false,
	--     gitcommit = false,
	--     gitrebase = false,
	--     hgcommit = false,
	--     svn = false,
	--     cvs = false,
	--     ["."] = false,
	--   },
	--   copilot_node_command = 'node', -- Node.js version must be > 18.x
	--   server_opts_overrides = {},
	-- })
	--     end,
	--   },
	{
		"zbirenbaum/copilot-cmp",
		after = { "copilot.lua" },
		config = function()
			require("copilot_cmp").setup()
		end,
	},
	{ "ellisonleao/gruvbox.nvim" },
	{ "MunifTanjim/nui.nvim" },
	{ "gabrielpoca/replacer.nvim" },
	{
		"iurimateus/luasnip-latex-snippets.nvim",
		-- vimtex isn't required if using treesitter
		dependencies = { "L3MON4D3/LuaSnip", "lervag/vimtex" },
		config = function()
			require("luasnip-latex-snippets").setup()
			-- or setup({ use_treesitter = true })
			require("luasnip").config.setup({ enable_autosnippets = true })
		end,
	},
}
