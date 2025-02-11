local operator = {}

operator.state = {
	pattern = "",
	visual = false,
	motion = "",
	wordBoundary = true,
}

local function cleanState()
	operator.state = {
		pattern = "",
		visual = false,
		motion = "",
		wordBoundary = true,
	}
end

local function getMarks()
	local s = vim.api.nvim_buf_get_mark(0, "[")
	local e = vim.api.nvim_buf_get_mark(0, "]")
	return { startRow = s[1], startCol = s[2], endRow = e[1], endCol = e[2] }
end

---@param opts? { pattern: string, motion: string, visual: boolean, wordBoundary: boolean }
function operator.operator(opts)
	cleanState()
	operator.state = vim.tbl_extend("force", operator.state, opts or {})
	vim.o.operatorfunc = "v:lua.require'multicursor-nvim.operator'.operatorCallback"

	if operator.state.pattern == "" then
		vim.api.nvim_feedkeys(string.format("g@%s", operator.state.motion or ""), "mi", false)
	else
		vim.api.nvim_feedkeys(string.format("g@l"), "mi", false)
	end
end

function operator.operatorCallback()
	if operator.state.pattern == "" then
		local marks = getMarks()
		operator.state.pattern = string.format(
			operator.state.wordBoundary and "\\<%s\\>" or "%s",
			vim.api.nvim_buf_get_text(0, marks.startRow - 1, marks.startCol, marks.endRow - 1, marks.endCol + 1, {})[1]
		)
	end
	vim.o.operatorfunc = "v:lua.require'multicursor-nvim.operator'.selectionOperatorCallback"
	vim.api.nvim_feedkeys(string.format("g@"), "mi", false)
end

function operator.selectionOperatorCallback()
	require("multicursor-nvim").matchCursorsRange(operator.state.pattern, getMarks(), operator.state.visual)
	cleanState()
end

return operator
