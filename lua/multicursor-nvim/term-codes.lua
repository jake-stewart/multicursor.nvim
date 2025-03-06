--- @type {[string]: string}
local TERM_CODES = {}
local mt = {}

--- @param k string
--- @return string
function mt.__index(t, k)
    local key = k:lower()
        :gsub("ctrl_", "c-")
        :gsub("meta_", "m-")
        :gsub("alt_", "a-")
        :gsub("shift_", "s-")
        :gsub("super_", "d-")
        :gsub("cmd_", "d-")
        :gsub("backspace", "bs")
        :gsub("_", "-")
    t[k] = vim.api.nvim_replace_termcodes(
        "<" .. key .. ">", true, true, true)
    return t[k]
end

return setmetatable(TERM_CODES, mt)
