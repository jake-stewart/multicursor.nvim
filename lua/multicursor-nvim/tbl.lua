local tbl = {}

--- @generic T
--- @param ... T[]
--- @return T[]
function tbl.concat(...)
    local result = {}
    for _, t in ipairs({...}) do
        for _, v in ipairs(t) do
            result[#result + 1] = v
        end
    end
    return result
end

--- @generic T
--- @param array T[]
--- @param start number
--- @param stop? number
--- @return T[]
function tbl.slice(array, start, stop)
    local n = #array
    start = math.max(start or 1, 1)
    stop = math.min(stop or n, n)
    local sliced = {}
    for i = start, stop do
        table.insert(sliced, array[i])
    end
    return sliced
end

--- @generic T
--- @generic Y
--- @param t T[]
--- @param callback fun(v: T, i: integer, t: T[]): Y
--- @return Y[]
function tbl.map(t, callback)
    local result = {}
    for i, v in ipairs(t) do
        result[#result + 1] = callback(v, i, t)
    end
    return result
end

--- @generic T
--- @param t T[]
--- @param callback fun(v: T, i: integer, t: T[])
function tbl.forEach(t, callback)
    for i, v in ipairs(t) do
        callback(v, i, t)
    end
end

--- @generic T
--- @param t T[]
--- @callback fun(v: T, i: integer, t: T[]): any
--- @return T[]
function tbl.filter(t, callback)
    local result = {}
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            result[#result + 1] = v
        end
    end
    return result
end

--- @generic T
--- @param t T[]
--- @param value T
function tbl.remove(t, value)
    local idx = tbl.indexOf(t, value)
    if idx then
        table.remove(t, idx)
    end
end

--- @generic T
--- @param t T[]
--- @callback fun(v: T, i: integer, t: T[]): any
--- @return T[], T[]
function tbl.bifurcate(t, callback)
    local matches = {}
    local rejects = {}
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            matches[#matches + 1] = v
        else
            rejects[#rejects + 1] = v
        end
    end
    return matches, rejects
end

function tbl.reduce(t, callback, initial)
    if initial then
        for i, v in ipairs(t) do
            initial = callback(initial, v, i, t)
        end
    else
        initial = t[1]
        for i = 2, #t do
            initial = callback(initial, t[i], i, t)
        end
    end
    return initial
end

--- @generic T
--- @param t T[]
--- @param callback fun(v: T, i: integer, t: T[]): any
--- @return T | nil
function tbl.find(t, callback)
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            return v
        end
    end
end

--- @generic T
--- @param t T[]
--- @param callback fun(v: T, i: integer, t: T[]): any
--- @return T | nil
function tbl.findLast(t, callback)
    for i = #t, 1, -1 do
        local v = t[i]
        if callback(v, i, t) then
            return v
        end
    end
end

function tbl.findIndex(t, callback)
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            return i
        end
    end
end

function tbl.indexOf(t, value)
    for i, v in ipairs(t) do
        if v == value then
            return i
        end
    end
end

function tbl.uniq(t)
    return tbl.filter(t, function(v, i)
        return tbl.indexOf(t, v) == i
    end)
end

--- @generic T
--- @param t T
--- @return T
function tbl.shallow_copy(t)
  local t2 = {}
  for k,v in pairs(t) do
    t2[k] = v
  end
  return t2
end

return tbl
