local util = {}

function util.echoerr(message, history)
    if history == nil then
        history = true
    end
    message = type(message) == "string"
        and message or vim.inspect(message)
    vim.api.nvim_echo({{message, "Error"}}, history, {})
end

function util.echowarn(message, history)
    if history == nil then
        history = true
    end
    message = type(message) == "string"
        and message or vim.inspect(message)
    vim.api.nvim_echo({{message, "WarningMsg"}}, history, {})
end

local alreadyWarned = {}
function util.warnOnce(key, message)
    if alreadyWarned[key] then
        return
    end
    alreadyWarned[key] = true
    util.echowarn(message)
end

--- @class mc.MatchListItem
--- @field idx integer
--- @field byteidx integer
--- @field text string
--- @field submatches string[]

--- Wraps `:h matchstrlist()` and allow injecting user options
--- for `:h smartcase`, `:h ignorecase`, and `:h magic`
--- @param lines string[]
--- @param pattern string
--- @param opts? { userConfig?: boolean }
--- @return mc.MatchListItem[]
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

--- Simple vimscript-esque autocommand wrapper
--- @param event string
--- @param pattern string
--- @param callback function
function util.au(event, pattern, callback)
    vim.api.nvim_create_autocmd(event, {
        pattern = pattern,
        callback = callback
    })
end

function util.removeStartFromEnd(a, b)
    local lenA = #a
    local lenB = #b
    local ret = a
    for i = 1, math.min(lenA, lenB) do
        if b:sub(1, i) == a:sub(lenA - i + 1) then
            ret = a:sub(1, lenA - i)
        end
    end
    return ret
end

return util
