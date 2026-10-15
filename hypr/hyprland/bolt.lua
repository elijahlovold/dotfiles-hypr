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
-- Skipped right after a Super+Ctrl+drag, whose modifier release would
-- otherwise end every drawing with a spiral.
local just_drew = false

function M.find_cursor()
    pcall(function()
        if just_drew then
            just_drew = false
            return
        end
        local p = hl.get_cursor_pos()
        if p then
            emit(string.format("cursor %d %d", math.floor(p.x + 0.5), math.floor(p.y + 0.5)))
        end
    end)
end

-- Super+Ctrl+left-drag draws a bolt trail behind the cursor. The only
-- polling in this file, and only while the button is held: a repeating
-- timer samples the cursor every DRAW_SAMPLE_MS and sends it on when it
-- moved. Capped at DRAW_MAX_MS in case the release is never seen.
local DRAW_SAMPLE_MS = 16
local DRAW_MAX_MS = 15000
local draw_timer = nil

local function cursor_xy()
    local p = hl.get_cursor_pos()
    if not p then
        return nil
    end
    return math.floor(p.x + 0.5), math.floor(p.y + 0.5)
end

function M.draw_stop()
    pcall(function()
        if not draw_timer then
            return
        end
        draw_timer:set_enabled(false)
        draw_timer = nil
        emit("drawend")
        -- The Super+Ctrl release that usually follows belongs to the drag.
        just_drew = true
        hl.timer(function()
            just_drew = false
        end, { timeout = 1500, type = "oneshot" })
    end)
end

function M.draw_start()
    pcall(function()
        if draw_timer then
            return
        end
        local lx, ly = cursor_xy()
        if not lx then
            return
        end
        emit(string.format("draw %d %d", lx, ly))
        local ticks = 0
        draw_timer = hl.timer(function()
            pcall(function()
                ticks = ticks + 1
                if ticks * DRAW_SAMPLE_MS > DRAW_MAX_MS then
                    M.draw_stop()
                    return
                end
                local x, y = cursor_xy()
                if x and (x ~= lx or y ~= ly) then
                    lx, ly = x, y
                    emit(string.format("draw %d %d", x, y))
                end
            end)
        end, { timeout = DRAW_SAMPLE_MS, type = "repeat" })
    end)
end

return M
