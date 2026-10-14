-- Feeds quickshell's lightning bolts (quickshell/modules/bolt). Hyprland
-- already knows the window geometry, so it's sent along as a custom socket2
-- event (`custom>>bolt:...`) that quickshell reads off the event socket it
-- already listens on - no process spawned, nothing polled. Whether a bolt is
-- actually drawn is decided on the quickshell side (BoltConfig.qml); with
-- quickshell not running these events just go nowhere.
--
-- Everything after the real dispatch is wrapped in pcall, so a problem here
-- can never break focus moves or window opening themselves.

local M = {}

local function xy(v)
    if type(v) ~= "table" then
        return nil
    end
    return v.x or v[1], v.y or v[2]
end

local function geom(w)
    local x, y = xy(w.at)
    local wd, ht = xy(w.size)
    if not (x and y and wd and ht) then
        return nil
    end
    local r = math.floor
    return string.format("%d %d %d %d", r(x + 0.5), r(y + 0.5), r(wd + 0.5), r(ht + 0.5))
end

local function emit(data)
    hl.dispatch(hl.dsp.event("bolt:" .. data))
end

-- Drop-in for hl.dsp.focus(spec) in binds: focuses, then reports where
-- focus jumped from and to.
function M.focus(spec)
    return function()
        local ok, before = pcall(hl.get_active_window)
        hl.dispatch(hl.dsp.focus(spec))
        if not ok or not before then
            return
        end
        pcall(function()
            local after = hl.get_active_window()
            if not after or after.address == before.address then
                return
            end
            local a, b = geom(before), geom(after)
            if a and b then
                emit("focus " .. a .. " " .. b)
            end
        end)
    end
end

hl.on("window.open", function(w)
    pcall(function()
        local g = geom(w)
        if g then
            emit("open " .. g .. " " .. (w.class or ""))
        end
    end)
end)

return M
