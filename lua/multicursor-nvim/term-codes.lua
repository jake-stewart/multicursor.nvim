local function termcode(key)
    return vim.api.nvim_replace_termcodes(key, true, true, true)
end

return {
    ESC = termcode("<esc>"),
    BACKSPACE = termcode("<bs>"),
    CTRL_A = termcode("<c-a>"),
    CTRL_X = termcode("<c-x>"),
    CTRL_V = termcode("<c-v>"),
    CTRL_S = termcode("<c-s>"),
    CTRL_R = termcode("<c-r>"),
    CTRL_G = termcode("<c-g>"),
    CTRL_E = termcode("<c-e>"),
    CTRL_Y = termcode("<c-y>"),
    CTRL_I = termcode("<c-i>"),
    CTRL_O = termcode("<c-o>"),
    LEFT = termcode("<left>"),
    RIGHT = termcode("<right>"),
}
