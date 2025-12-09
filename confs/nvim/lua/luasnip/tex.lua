local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local l = require("luasnip.extras").lambda
local rep = require("luasnip.extras").rep
local p = require("luasnip.extras").partial
local m = require("luasnip.extras").match
local n = require("luasnip.extras").nonempty
local dl = require("luasnip.extras").dynamic_lambda
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta
local types = require("luasnip.util.types")
local conds = require("luasnip.extras.conditions")
local conds_expand = require("luasnip.extras.conditions.expand")

return {
	-- HTML-based
	s(
		{ trig = ";ul", snippetType = "autosnippet" },
		fmta(
			[[
    \begin{itemize}
    \item <>
    \end{itemize}
    ]],
			{ i(1) }
		)
	),
	s(
		{ trig = ";ol", snippetType = "autosnippet" },
		fmta(
			[[
    \begin{enumerate}
    \item <>
    \end{enumerate}
    ]],
			{ i(1) }
		)
	),
	s({ trig = ";li", snippetType = "autosnippet" }, { t("\\item\n    "), i(1) }),
	s({ trig = ";b", snippetType = "autosnippet" }, fmta([[\textbf{<>}]], { i(1) })),
	s({ trig = ";i", snippetType = "autosnippet" }, fmta([[\textit{<>}]], { i(1) })),
	s({ trig = ";h1", snippetType = "autosnippet" }, fmta([[\section{<>}]], { i(1, "Title") })),
	s({ trig = ";h2", snippetType = "autosnippet" }, fmta([[\subsection{<>}]], { i(1, "Title") })),
	s({ trig = ";h3", snippetType = "autosnippet" }, fmta([[\subsubsection{<>}]], { i(1, "Title") })),
	s({ trig = ";h4", snippetType = "autosnippet" }, fmta([[\paragraph{<>}]], { i(1, "Title") })),
	s({ trig = ";h5", snippetType = "autosnippet" }, fmta([[\subparagraph{<>}]], { i(1, "Title") })),
}
