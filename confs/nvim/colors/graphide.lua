-- Verdigris Ink: the same neutrals, syntax hues, and accent as the desktop palette.
vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end
vim.g.colors_name = "graphide"

local p = {
	ink = "#0a1218",
	raised = "#0f1a22",
	selection = "#18242c",
	hairline = "#52616b",
	muted = "#75838b",
	text = "#bcc6cd",
	bright = "#dae1e6",
	white = "#ffffff",
	red = "#f85149",
	orange = "#f78c6c",
	yellow = "#e3b341",
	green = "#c3e88d",
	accent = "#4fa396",
	blue = "#8aaeff",
	purple = "#c792ea",
	soft = "#79b0a8",
}

local highlights = {
	Normal = { fg = p.text, bg = p.ink },
	NormalNC = { fg = p.text, bg = p.ink },
	NormalFloat = { fg = p.text, bg = p.raised },
	FloatBorder = { fg = p.accent, bg = p.raised },
	FloatTitle = { fg = p.soft, bg = p.raised, bold = true },
	WinSeparator = { fg = p.hairline },
	Cursor = { fg = p.ink, bg = p.accent },
	CursorLine = { bg = p.raised },
	CursorColumn = { bg = p.raised },
	ColorColumn = { bg = p.raised },
	LineNr = { fg = p.muted },
	CursorLineNr = { fg = p.soft, bold = true },
	SignColumn = { fg = p.muted, bg = p.ink },
	FoldColumn = { fg = p.muted, bg = p.ink },
	Folded = { fg = p.muted, bg = p.raised },
	NonText = { fg = p.hairline },
	Whitespace = { fg = p.hairline },
	EndOfBuffer = { fg = p.hairline },
	Visual = { bg = p.selection },
	Search = { fg = p.ink, bg = p.soft },
	IncSearch = { fg = p.ink, bg = p.yellow },
	CurSearch = { fg = p.ink, bg = p.yellow, bold = true },
	MatchParen = { fg = p.soft, bg = p.selection, bold = true },
	Pmenu = { fg = p.text, bg = p.raised },
	PmenuSel = { fg = p.ink, bg = p.accent },
	PmenuSbar = { bg = p.selection },
	PmenuThumb = { bg = p.muted },
	StatusLine = { fg = p.text, bg = p.raised },
	StatusLineNC = { fg = p.muted, bg = p.raised },
	TabLine = { fg = p.muted, bg = p.raised },
	TabLineFill = { bg = p.ink },
	TabLineSel = { fg = p.soft, bg = p.selection, bold = true },
	WinBar = { fg = p.soft, bg = p.ink },
	WinBarNC = { fg = p.muted, bg = p.ink },
	Title = { fg = p.soft, bold = true },
	Directory = { fg = p.blue },
	MoreMsg = { fg = p.soft },
	Question = { fg = p.soft },
	ModeMsg = { fg = p.soft },
	ErrorMsg = { fg = p.red },
	WarningMsg = { fg = p.yellow },
	Comment = { fg = p.muted, italic = true },
	Constant = { fg = p.orange },
	String = { fg = p.green },
	Character = { fg = p.green },
	Number = { fg = p.orange },
	Boolean = { fg = p.orange },
	Float = { fg = p.orange },
	Identifier = { fg = p.text },
	Function = { fg = p.blue },
	Statement = { fg = p.purple },
	Operator = { fg = p.soft },
	Keyword = { fg = p.purple },
	PreProc = { fg = p.soft },
	Type = { fg = p.yellow },
	Special = { fg = p.soft },
	Delimiter = { fg = p.text },
	Underlined = { fg = p.blue, underline = true },
	Ignore = { fg = p.muted },
	Error = { fg = p.red },
	Todo = { fg = p.yellow, bg = p.raised, bold = true },
	DiffAdd = { bg = "#14251e" },
	DiffChange = { bg = "#152336" },
	DiffText = { bg = "#233551", bold = true },
	DiffDelete = { fg = p.red, bg = "#2b191e" },
	GitSignsAdd = { fg = p.green },
	GitSignsChange = { fg = p.blue },
	GitSignsDelete = { fg = p.red },
	TelescopeBorder = { fg = p.accent },
	TelescopeSelection = { bg = p.selection },
	TelescopeMatching = { fg = p.soft, bold = true },
	WhichKey = { fg = p.soft },
	WhichKeyGroup = { fg = p.blue },
	WhichKeyDesc = { fg = p.text },
	WhichKeySeparator = { fg = p.muted },
	["@variable"] = { fg = p.text },
	["@variable.builtin"] = { fg = p.orange },
	["@variable.parameter"] = { fg = p.text },
	["@property"] = { fg = p.soft },
	["@markup.heading"] = { fg = p.soft, bold = true },
	["@markup.strong"] = { bold = true },
	["@markup.italic"] = { italic = true },
	["@markup.strikethrough"] = { strikethrough = true },
	["@markup.raw"] = { fg = p.green },
	["@markup.link.url"] = { fg = p.blue, underline = true },
	["@markup.list"] = { fg = p.soft },
}

for name, color in pairs({ Error = p.red, Warn = p.yellow, Info = p.blue, Hint = p.soft, Ok = p.green }) do
	highlights["Diagnostic" .. name] = { fg = color }
	highlights["DiagnosticVirtualText" .. name] = { fg = color, bg = p.raised }
	highlights["DiagnosticUnderline" .. name] = { sp = color, undercurl = true }
end
for name, color in pairs({ Bad = p.red, Cap = p.blue, Rare = p.purple, Local = p.soft }) do
	highlights["Spell" .. name] = { sp = color, undercurl = true }
end
for name, attributes in pairs(highlights) do
	vim.api.nvim_set_hl(0, name, attributes)
end

local terminal = {
	p.ink,
	p.red,
	p.green,
	p.yellow,
	p.blue,
	p.purple,
	p.accent,
	p.text,
	p.hairline,
	p.red,
	p.green,
	p.yellow,
	p.blue,
	p.purple,
	p.accent,
	p.white,
}
for index, color in ipairs(terminal) do
	vim.g["terminal_color_" .. (index - 1)] = color
end
