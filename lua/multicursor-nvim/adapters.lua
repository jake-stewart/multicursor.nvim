local function NO_OP()
end

local TOGGLABLE_ADAPTERS = {
    ["which-key.view"] = {
        state = {},
        enabled = function(m)
            return m.update ~= NO_OP
        end,
        setEnabled = function(m, enabled)
            if enabled then
                m.update = m._update or m.update
            else
                m._update = m.update
                m.update = NO_OP
            end
        end
    },
    ["snacks.scroll"] = {
        state = {},
        enabled = function(m)
            return m.enabled
        end,
        setEnabled = function(m, enabled)
            if enabled then
                m.enable()
            else
                m.disable()
            end
        end
    },
    ["hardtime"] = {
        state = {},
        enabled = function(m)
            return m.is_plugin_enabled
        end,
        setEnabled = function(m, enabled)
            if enabled then
                m.enable()
            else
                m.disable()
            end
        end,
    },
}

local adapters = {}

function adapters.disable()
    for k, v in pairs(TOGGLABLE_ADAPTERS) do
        if v.state.enabled == nil then
            v.state.enabled = false
            if package.loaded[k] then
                local msuccess, m = pcall(require, k)
                if msuccess then
                    local success, enabled = pcall(v.enabled, m)
                    v.state.enabled = success and (enabled or false)
                    if v.state.enabled then
                        v.setEnabled(m, false)
                    end
                end
            end
        end
    end
end

function adapters.enable()
    for k, v in pairs(TOGGLABLE_ADAPTERS) do
        if v.state.enabled then
            if package.loaded[k] then
                local msuccess, m = pcall(require, k)
                if msuccess then
                    v.setEnabled(m, true)
                end
            end
        end
        v.state.enabled = nil
    end
end

return adapters
