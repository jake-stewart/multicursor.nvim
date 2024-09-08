local function matchlist(lines, pattern, opts)
    opts = opts or {}
    if opts.userConfig then
        if vim.o.ignorecase then
            if vim.o.smartcase and string.find(pattern, "[A-Z]") then
                pattern = "\\C" .. pattern
            else
                pattern = "\\c" .. pattern
            end
        end
        if vim.o.magic then
            pattern = "\\m" .. pattern
        else
            pattern = "\\M" .. pattern
        end
    end
    return vim.fn.matchstrlist(lines, pattern)
end

return matchlist
