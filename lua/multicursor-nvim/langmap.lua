local langmap = ""
local langmap_table = {}

local function iter_chars(s)
    local i = 0
    local char
    return function()
        if i < #s then
            char = vim.fn.strpart(s, i, 1, 1)
            i = i + #char
            return char
        end
    end
end

local function create_langmap()
    langmap_table = {}

    local items = {}
    local escaped = false
    local current = { from = {} }
    for char in iter_chars(langmap) do
        if escaped then
            table.insert(current.to or current.from, char)
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif char == "," then
            table.insert(items, current)
            current = { from = {} }
        elseif char == ";" then
            current.to = current.to or {}
        else
            table.insert(current.to or current.from, char)
        end
    end
    table.insert(items, current)

    for _, item in ipairs(items) do
        if #item.from > 0 then
            if item.to then
                for i, fromChar in ipairs(item.from) do
                    if not item.to[i] then
                        break
                    end
                    langmap_table[fromChar] = item.to[i]
                end
            else
                local i = 1
                while i < #item.from do
                    langmap_table[item.from[i]] = item.from[i + 1]
                    i = i + 2
                end
            end
        end
    end
end

local function apply_langmap(s)
    if vim.o.langmap ~= langmap then
        langmap = vim.o.langmap
        create_langmap()
    end

    if langmap == "" then
        return s
    end

    local result = {}
    for char in iter_chars(s) do
        table.insert(result, langmap_table[char] or char)
    end
    return table.concat(result)
end

return apply_langmap
