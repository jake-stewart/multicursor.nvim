local util = {}

function util.echoerr(message)
    message = type(message) == "string"
        and message or vim.inspect(message)
    vim.api.nvim_echo({{message, "Error"}}, false, {})
end

--- wraps `:h matchstrlist()` and allow injecting user options
--- for `:h smartcase`, `:h ignorecase`, and `:h magic`
--- @param lines string[]
--- @param pattern string
--- @param opts? { userConfig?: boolean }
function util.matchlist(lines, pattern, opts)
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

--- simple vimscript-esque autocommand wrapper
--- @param event string
--- @param pattern string
--- @param callback function
function util.au(event, pattern, callback)
    vim.api.nvim_create_autocmd(event, {
        pattern = pattern,
        callback = callback
    })
end

return util
