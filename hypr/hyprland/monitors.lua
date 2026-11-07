-- The one place outputs are named. Everything else (rules.lua's scroll
-- direction, quickshell's bar/overlays, the wallpaper) goes by each
-- monitor's orientation, so none of it needs editing when this does.
--
-- outputs: per-output settings, applied whenever that output is enabled.
-- An output not listed here runs on Hyprland's defaults (preferred mode,
-- auto position).
--
-- profiles: sets of outputs enabled together; Super+Shift+M (keybinds.lua)
-- cycles through the ones whose outputs are all connected. Listed outputs
-- outside the active profile are disabled. The first output of a profile
-- is where workspaces land when switching to it. Leave profiles empty and
-- every connected monitor just stays on, untouched.

local M = {}

local outputs = {
    ["DP-1"] = { mode = "1920x1080@60", position = "0x0", scale = 1, transform = 3 },
    ["DP-2"] = { mode = "3840x2160@60", position = "auto", scale = "auto" },
    ["HDMI-A-1"] = { mode = "1920x1080@60", position = "auto", scale = "auto" },
}

local profiles = {
    { "DP-2", "DP-1" }, -- dual: 4K + portrait
    { "HDMI-A-1" }, -- solo
}

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

-- hl.monitor() merges onto the existing rule for an output, so `disabled`
-- is always passed explicitly.
local function enable(name)
    local spec = { output = name, disabled = false }
    for k, v in pairs(outputs[name] or {}) do
        spec[k] = v
    end
    hl.monitor(spec)
end

local function disable(name)
    hl.monitor({ output = name, disabled = true })
end

-- name -> true, for active (enabled) monitors, or with all = every
-- connected one, disabled included.
local function monitorSet(all)
    local set = {}
    for _, m in ipairs(hl.get_monitors({ all = all }) or {}) do
        set[m.name] = true
    end
    return set
end

local function covers(profile, set)
    for _, name in ipairs(profile) do
        if not set[name] then
            return false
        end
    end
    return true
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

-- Index of the profile currently showing: the first whose outputs are all
-- active. nil when none is (e.g. before any monitor is up).
local function current()
    local active = monitorSet(false)
    for i, p in ipairs(profiles) do
        if covers(p, active) then
            return i
        end
    end
    return nil
end

-- A switch waiting on its outputs to come up (monitor.added).
local pending = nil

-- Second half of a switch, once the target's outputs are all active.
-- Disabling an output does NOT migrate its workspaces (known, deliberately
-- unfixed: https://github.com/hyprwm/Hyprland/issues/5052) - left alone a
-- workspace stays assigned to a monitor that no longer exists, its windows
-- unreachable. So every workspace on an output being turned off is moved to
-- the target first, while both are still up. Special workspaces (scratchpad,
-- negative ids) are left alone.
local function finish()
    local profile = pending
    if not profile or not covers(profile, monitorSet(false)) then
        return
    end
    pending = nil
    local leaving = {}
    for name in pairs(outputs) do
        if not contains(profile, name) then
            leaving[name] = true
        end
    end
    for _, ws in ipairs(hl.get_workspaces() or {}) do
        if not ws.special and ws.monitor and leaving[ws.monitor.name] then
            hl.dispatch(hl.dsp.workspace.move({ workspace = ws.id, monitor = profile[1] }))
        end
    end
    for name in pairs(leaving) do
        disable(name)
    end
    -- Monitor ids/rotations changed: rebuild the screen shader's
    -- per-monitor rotation table (no-op if none is on).
    hl.exec_cmd("command -v hypr-shader >/dev/null && hypr-shader refresh")
end

local function apply(profile)
    pending = profile
    for _, name in ipairs(profile) do
        enable(name)
    end
    -- Already up (or enabled synchronously); otherwise monitor.added
    -- finishes it.
    finish()
end

hl.on("monitor.added", finish)

-- Super+Shift+M: the next profile whose outputs are all connected.
function M.next_profile()
    if #profiles == 0 then
        return
    end
    local connected = monitorSet(true)
    local start = current() or 0
    for step = 1, #profiles do
        local i = (start + step - 1) % #profiles + 1
        if i ~= start and covers(profiles[i], connected) then
            apply(profiles[i])
            return
        end
    end
end

-- On load (startup or config reload): keep whichever profile is showing,
-- so a reload doesn't undo a switch; otherwise the first. Nothing to
-- migrate here - outputs outside the profile are already off (reload) or
-- have no workspaces yet (startup) - so they're just disabled up front.
if #profiles > 0 then
    local profile = profiles[current() or 1]
    for name in pairs(outputs) do
        if contains(profile, name) then
            enable(name)
        else
            disable(name)
        end
    end
end

return M
