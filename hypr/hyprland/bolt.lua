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

-- Drop-in for hl.dsp.exec_cmd(cmd) in binds that open an app: remembers
-- which window had focus (none = nothing focused), so the window that opens
-- next can be struck from it - or get a small spiral if there was no source.
local pending = nil

function M.exec(cmd)
    return function()
        pcall(function()
            local w = hl.get_active_window()
            pending = { address = w and w.address or false }
            emit("launch")
        end)
        hl.dispatch(hl.dsp.exec_cmd(cmd))
    end
end

local function find_window(address)
    for _, w in ipairs(hl.get_windows()) do
        if w.address == address then
            return w
        end
    end
    return nil
end

-- `bolt:open x y w h <src> <class>` - src is the launching window's current
-- geometry as "x,y,w,h", "spiral" (launched with nothing focused) or "-"
-- (not opened via M.exec). Quickshell drops a src whose launch is too old.
hl.on("window.open", function(w)
    pcall(function()
        local g = geom(w)
        if not g then
            return
        end
        local src = "-"
        if pending then
            local from = pending.address and find_window(pending.address)
            local fg = from and from.address ~= w.address and geom(from)
            src = fg and fg:gsub(" ", ",") or "spiral"
            pending = nil
        end
        emit("open " .. g .. " " .. src .. " " .. (w.class or ""))
    end)
end)

-- Super+Ctrl tapped on their own - like Windows' "show pointer location":
-- quickshell draws a bolt spiralling in onto the cursor (keybinds.lua).
function M.find_cursor()
    pcall(function()
        local p = hl.get_cursor_pos()
        if p then
            emit(string.format("cursor %d %d", math.floor(p.x + 0.5), math.floor(p.y + 0.5)))
        end
    end)
end

return M
