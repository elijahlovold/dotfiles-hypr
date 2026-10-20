require("hyprland.variables")
local bolt = require("hyprland.bolt")

local mod = "SUPER"

--- core window management (i3: h/j/k/l focus, mod+q kill, etc.) ---
hl.bind(mod .. " + Q", hl.dsp.window.close())

hl.bind(mod .. " + CTRL + SHIFT + E", hl.dsp.exit())
-- i3: mod+space "focus mode_toggle" - jump between the floating and tiled
-- layers of the current workspace, landing on whichever window of the other
-- layer was focused most recently (lowest focus_history_id).
hl.bind(mod .. " + Space", function()
    local active = hl.get_active_window()
    if not active or not active.workspace then
        return
    end
    local target
    for _, w in ipairs(hl.get_windows({ workspace = active.workspace, floating = not active.floating, mapped = true })) do
        if not w.hidden and (not target or w.focus_history_id < target.focus_history_id) then
            target = w
        end
    end
    if target then
        bolt.focus({ window = target })()
    end
end)
hl.bind(mod .. " + SHIFT + Space", hl.dsp.window.float({ action = "toggle" }))
-- Show/hide the quickshell bar (quickshell/modules/bar/Bar.qml listens for
-- this custom event - same route as the bolts, no process spawned).
hl.bind(mod .. " + CTRL + Space", hl.dsp.event("bar:toggle"))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))

-- i3: mod+s layout stacking / mod+w layout tabbed -> Hyprland's window groups are the
-- closest equivalent to both (there's no separate stacked-vs-tabbed container type).
hl.bind(mod .. " + S", hl.dsp.group.toggle())

hl.bind(mod .. " + W", hl.dsp.layout("fit active"))
hl.bind(mod .. " + E", hl.dsp.layout("fit toend"))

-- Move focus with vim keys. bolt.focus = hl.dsp.focus + a lightning bolt
-- between the two windows (hyprland/bolt.lua, quickshell/modules/bolt).
hl.bind(mod .. " + K", bolt.focus({ direction = "u" }))
hl.bind(mod .. " + J", bolt.focus({ direction = "d" }))
hl.bind(mod .. " + Up", bolt.focus({ direction = "u" }))
hl.bind(mod .. " + Down", bolt.focus({ direction = "d" }))
hl.bind(mod .. " + H", bolt.focus({ direction = "l" }))
hl.bind(mod .. " + L", bolt.focus({ direction = "r" }))
hl.bind(mod .. " + Left",  bolt.focus({ direction = "l" }))
hl.bind(mod .. " + Right", bolt.focus({ direction = "r" }))

-- Super+Ctrl: bolt onto the cursor to find it (hyprland/bolt.lua). On
-- release of whichever of the two goes first (both mods are still held at
-- that point), so it doesn't fire on the way into Super+Ctrl+<key> chords -
-- release binds only fire when nothing else was pressed in between.
for _, key in ipairs({ "Control_L", "Control_R", "Super_L", "Super_R" }) do
    hl.bind("SUPER + CTRL + " .. key, bolt.find_cursor, { release = true, non_consuming = true })
end

-- Super+Ctrl+left-drag: draw a bolt behind the cursor (hyprland/bolt.lua).
-- The release is bound ignoring modifiers, so letting go of Super/Ctrl
-- before the button still ends the drawing; non_consuming, so ordinary
-- clicks are untouched.
hl.bind(mod .. " + CTRL + mouse:272", bolt.draw_start)
hl.bind("mouse:272", bolt.draw_stop, { release = true, ignore_mods = true, non_consuming = true })

-- Scrolling layout
hl.bind(mod .. " + period", hl.dsp.layout("swapcol r"))
hl.bind(mod .. " + comma", hl.dsp.layout("swapcol l"))

-- Move window with Shift + vim keys
hl.bind(mod .. " + SHIFT + H", hl.dsp.window.move({ direction = "l" }))
hl.bind(mod .. " + SHIFT + L", hl.dsp.window.move({ direction = "r" }))
hl.bind(mod .. " + SHIFT + K", hl.dsp.window.move({ direction = "u" }))
hl.bind(mod .. " + SHIFT + J", hl.dsp.window.move({ direction = "d" }))

-- i3 binds Shift+arrows to resize (not move) - kept as-is for fidelity.
hl.bind(mod .. " + SHIFT + Left",  hl.dsp.window.resize({ x = -30, y = 0, relative = true }))
hl.bind(mod .. " + SHIFT + Down",  hl.dsp.window.resize({ x = 0, y = 30, relative = true }))
hl.bind(mod .. " + SHIFT + Up",    hl.dsp.window.resize({ x = 0, y = -30, relative = true }))
hl.bind(mod .. " + SHIFT + Right", hl.dsp.window.resize({ x = 30, y = 0, relative = true }))

hl.bind(mod .. " + minus", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + minus", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mod .. " + N", hl.dsp.workspace.move({ monitor = "+1" }))
hl.bind(mod .. " + SHIFT + N", hl.dsp.workspace.move({ monitor = "-1" }))

hl.bind(mod .. " + Tab", bolt.focus({ direction = "r" }))
hl.bind(mod .. " + SHIFT + Tab", bolt.focus({ direction = "l" }))

-- i3: mod+g bounces 11 -> focus left -> 12 -> focus right -> back to 11
hl.bind(mod .. " + G", function()
    hl.dispatch(hl.dsp.focus({ workspace = 11 }))
    hl.dispatch(hl.dsp.focus({ direction = "l" }))
    hl.dispatch(hl.dsp.focus({ workspace = 12 }))
    hl.dispatch(hl.dsp.focus({ direction = "r" }))
    hl.dispatch(hl.dsp.focus({ workspace = 11 }))
end)

-- Switch workspaces with mod + [0-9]
-- Move active window to a workspace with mod + SHIFT + [0-9]
for i = 1, 10 do
    local key = tostring(i % 10) -- 10 maps to key 0
    hl.bind(mod .. " + " .. key, bolt.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- mod+alt+[0-9]: jump to workspace and launch its app (i3 $mod+Mod1+N)
local function workspace_exec(workspace, command)
    return function()
        hl.dispatch(bolt.focus({ workspace = workspace }))
        if command then
            hl.exec_cmd(command)
        end
    end
end

hl.bind(mod .. " + ALT + 1", workspace_exec(1, "google-chrome --new-window https://calendar.google.com/calendar/u/0/r"))
hl.bind(mod .. " + ALT + 2", workspace_exec(2, "slack"))
hl.bind(mod .. " + ALT + 3", workspace_exec(3, terminal .. " --working-directory /var/lib/cadence"))
hl.bind(mod .. " + ALT + 4", workspace_exec(4, terminal .. " --working-directory ~/repos"))
hl.bind(mod .. " + ALT + 5", workspace_exec(5))
hl.bind(mod .. " + ALT + 6", workspace_exec(6, "firefox"))
hl.bind(mod .. " + ALT + 7", workspace_exec(7, "firefox --new-window https://youtube.com/"))
hl.bind(mod .. " + ALT + 8", workspace_exec(8, "obsidian"))
hl.bind(mod .. " + ALT + 9", workspace_exec(9, "firefox --new-window https://chatgpt.com/"))
hl.bind(mod .. " + ALT + 0", workspace_exec(10, "spotify"))


hl.bind(mod .. " + mouse_down", hl.dsp.layout("move -400"))
hl.bind(mod .. " + mouse_up", hl.dsp.layout("move 400"))

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- --- resize mode (i3's `mode "resize"`) ---
hl.bind(mod .. " + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    local repeat_opts = { repeating = true }

    hl.bind("h",     hl.dsp.window.resize({ x = -10, y = 0,   relative = true }), repeat_opts)
    hl.bind("l",     hl.dsp.window.resize({ x = 10,  y = 0,   relative = true }), repeat_opts)
    hl.bind("k",     hl.dsp.window.resize({ x = 0,   y = 10,  relative = true }), repeat_opts)
    hl.bind("j",     hl.dsp.window.resize({ x = 0,   y = -10, relative = true }), repeat_opts)
    hl.bind("Left",  hl.dsp.window.resize({ x = -10, y = 0,   relative = true }), repeat_opts)
    hl.bind("Down",  hl.dsp.window.resize({ x = 0,   y = 10,  relative = true }), repeat_opts)
    hl.bind("Up",    hl.dsp.window.resize({ x = 0,   y = -10, relative = true }), repeat_opts)
    hl.bind("Right", hl.dsp.window.resize({ x = 10,  y = 0,   relative = true }), repeat_opts)

    hl.bind("Return", hl.dsp.submap("reset"))
    hl.bind("Escape", hl.dsp.submap("reset"))
    hl.bind(mod .. " + R", hl.dsp.submap("reset"))
end)

hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))

hl.bind(mod .. " + CTRL + SHIFT + X", hl.dsp.exec_cmd("poweroff"))
hl.bind(mod .. " + CTRL + SHIFT + R", hl.dsp.exec_cmd("reboot"))

-- Native Lua replacement for the old `hyprctl keyword ... | jq` blur toggle.
hl.bind(mod .. " + SHIFT + C", function()
    local enabled = hl.get_config("decoration.blur.enabled")
    local opacity = enabled and 1.0 or 0.6
    hl.config({
        decoration = {
            blur = {
                enabled = not enabled,
            },
            inactive_opacity = opacity,
        },
    })
end)

-- --- gaps live-adjust ---
-- Hyprland gaps are global-only, no per-workspace local vs. global distinction like i3 had.
local function adjust_gap(name, delta)
    local value = hl.get_config("general." .. name)
    local current = type(value) == "table" and value.top or value

    hl.config({
        general = {
            [name] = current + delta,
        },
    })
end

hl.bind(mod .. " + Z",                function() adjust_gap("gaps_in",  5) end)
hl.bind(mod .. " + SHIFT + Z",        function() adjust_gap("gaps_in", -5) end)
hl.bind(mod .. " + CTRL + Z",         function() adjust_gap("gaps_out",  5) end)
hl.bind(mod .. " + CTRL + SHIFT + Z", function() adjust_gap("gaps_out", -5) end)

-- --- screenshots ---

local screenshots = "$(xdg-user-dir PICTURES)/screenshots"

hl.bind("Print", hl.dsp.exec_cmd(
    'file="' .. screenshots .. '/$(date +%Y-%m-%d_%H-%M-%S).png"; ' ..
    'grim -g "$(slurp)" "$file" && wl-copy < "$file"'
))

hl.bind(mod .. " + ALT + Print", hl.dsp.exec_cmd("hypr-ocr"))
hl.bind(mod .. " + CTRL + Print", hl.dsp.exec_cmd("hypr-screenrec toggle"))
hl.bind(mod .. " + Print", hl.dsp.exec_cmd(
    'file="' .. screenshots .. '/$(date +%Y-%m-%d_%H-%M-%S).png"; ' ..
    'output="$(hyprctl -j monitors | jq -r \'.[] | select(.focused).name\')"; ' ..
    'grim -o "$output" "$file" && wl-copy < "$file"'
))

hl.bind("SUPER + SHIFT + Print", hl.dsp.exec_cmd(
    'file="$(find "' .. screenshots .. '" -maxdepth 1 -type f -name \'*.png\' -printf \'%T@ %p\\n\' ' ..
    '| sort -nr | head -1 | cut -d\' \' -f2-)"; ' ..
    '[ -n "$file" ] && satty -f "$file" --copy-command wl-copy'
))

-- --- apps ---
-- Quickshell keytree + utils
hl.bind(mod .. " + D", hl.dsp.exec_cmd("qs ipc call keytree toggle default"))
hl.bind(mod .. " + Y", hl.dsp.exec_cmd("qs ipc call keytree toggle stator"))
hl.bind(mod .. " + P", hl.dsp.exec_cmd("qs ipc call keytree toggle popups"))
hl.bind(mod .. " + O", hl.dsp.exec_cmd("qs ipc call keytree toggle dirs"))
hl.bind(mod .. " + B", hl.dsp.exec_cmd("qs ipc call keybinds toggle"))
hl.bind(mod .. " + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"))

-- App launchers: bolt.exec = hl.dsp.exec_cmd + a bolt from the focused
-- window to the new one (or a small spiral on it if nothing had focus).
hl.bind(mod .. " + Return", bolt.exec(terminal))
hl.bind(mod .. " + X", bolt.exec("firefox"))
hl.bind(mod .. " + ALT + X", bolt.exec("firefox --private-window"))
hl.bind(mod .. " + SHIFT + X", bolt.exec("google-chrome"))

hl.bind(mod .. " + SHIFT + O", bolt.exec("alacritty --working-directory $(mount.sh)"))

hl.bind(mod .. " + I", bolt.exec("kitty --working-directory ~/vault -e nvim"))
hl.bind(mod .. " + SHIFT + I", bolt.exec("kitty --working-directory ~/reposc/vault -e nvim"))
hl.bind(mod .. " + T", bolt.exec(terminal .. " --working-directory ~/vault -e nvim $(todays-notes)"))

hl.bind(mod .. " + M", bolt.exec(terminal .. " --class btop -e btop"))

hl.bind(mod .. " + ALT + Return", hl.dsp.exec_cmd("spotify-queue"), { release = true })

hl.bind("SUPER + grave", hl.dsp.exec_cmd('wtype -s 150 "$(date +%F)"'))

hl.bind(mod .. " + C", hl.dsp.exec_cmd("wallpaper-picker"))
hl.bind(mod .. " + CTRL + C", hl.dsp.exec_cmd("wallpaper-picker --stop"))
hl.bind(mod .. " + CTRL + SHIFT + C", hl.dsp.exec_cmd("wallpaper-picker --clear"))

-- Toggle dual monitors (DP-1 + DP-2) vs. solo third monitor (HDMI-A-1) - see toggle-monitors
hl.bind(mod .. " + SHIFT + M", hl.dsp.exec_cmd("hypr-toggle-monitors"))

hl.bind(mod .. " + U", bolt.exec("firefox --new-window https://www.stevenspass.com/the-mountain/mountain-conditions/mountain-cams.aspx"))
hl.bind(mod .. " + SHIFT + U", hl.dsp.exec_cmd("wallpaper-picker --sp"))

hl.bind(mod .. " + SHIFT + P", hl.dsp.exec_cmd("rofimoji"))
hl.bind(mod .. " + CTRL + P", hl.dsp.exec_cmd("password-picker"))

-- -- --- stats overlay mode (i3: mod+apostrophe hold-to-show) ---
-- hl.bind(mod .. " + apostrophe", hl.dsp.exec_cmd("/home/elovold/sdbx/cpp_overlay/build/overlay"))
-- hl.bind(mod .. " + apostrophe", hl.dsp.submap("stats"))
-- hl.define_submap("stats", function()
--     hl.bind(mod .. " + apostrophe", hl.dsp.exec_cmd("pkill -f overlay"), { release = true })
--     hl.bind(mod .. " + apostrophe", hl.dsp.submap("reset"), { release = true })
-- end)

-- --- media / volume keys ---
hl.bind("XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5% && paplay /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga"),
    { locked = true, repeating = true })

hl.bind("XF86AudioLowerVolume",
    hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5% && paplay /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga"),
    { locked = true, repeating = true })

hl.bind("XF86AudioMute",
    hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"),
    { locked = true, repeating = true })

hl.bind("XF86AudioMicMute",
    hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"),
    { locked = true, repeating = true })

hl.bind("XF86MonBrightnessUp",
    hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),
    { locked = true, repeating = true })

hl.bind("XF86MonBrightnessDown",
    hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),
    { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("SHIFT + XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause --all-players"), { locked = true })

-- mod+alt+hjkl/space media shortcuts
hl.bind(mod .. " + ALT + L", hl.dsp.exec_cmd("playerctl next"))
hl.bind(mod .. " + ALT + H", hl.dsp.exec_cmd("playerctl previous"))
hl.bind(mod .. " + ALT + K", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"))
hl.bind(mod .. " + ALT + J", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"))
hl.bind(mod .. " + ALT + Space", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind(mod .. " + ALT + SHIFT + Space", hl.dsp.exec_cmd("playerctl play-pause --all-players"))

