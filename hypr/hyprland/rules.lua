-- Portrait monitors scroll down instead of right (appearance.lua's
-- default). Workspace rules can only select a monitor by name, so one is
-- made per monitor as it shows up and switched on/off by its orientation:
-- rotated a quarter turn (odd transform) flips its mode's own shape.
local portraitRules = {}

local function syncScrollDirections()
    for _, m in ipairs(hl.get_monitors() or {}) do
        local portrait = (m.width < m.height) ~= (m.transform % 2 == 1)
        local rule = portraitRules[m.name]
        if not rule and portrait then
            rule = hl.workspace_rule({
                workspace = "m[" .. m.name .. "]",
                layout_opts = {
                    direction = "down",
                },
            })
            portraitRules[m.name] = rule
        end
        if rule then
            rule:set_enabled(portrait)
        end
    end
end

syncScrollDirections()
hl.on("monitor.added", syncScrollDirections)
hl.on("monitor.layout_changed", syncScrollDirections)

hl.window_rule({
    name = "generic-float",
    match = { class = "^(ui_service\\.py|launch_workstation\\.py|hyprland-share-picker)$" },
    float = true,
})

hl.window_rule({
    match = {
        class = "(?i)^(nsxiv|com.gabm.satty|mpv|org.pulseaudio.pavucontrol)$"
    },
    float = true,
    center = true,
    size = { "(monitor_w*0.65)", "(monitor_h*0.70)" },
})

hl.window_rule({
    match = {
        class = "^btop$"
    },
    float = true,
    center = true,
    size = { "(monitor_w*0.90)", "(monitor_h*0.70)" },
})

-- -- (Stale: keytree now lives in the shared "quickshell:overlay" layer, so
-- -- this namespace no longer exists.)
-- -- Real compositor blur for Keytree's disc (see
-- -- quickshell/modules/keytree/KeytreePanel.qml's BackgroundEffect.blurRegion).
-- -- ignore_alpha is required: the disc content is a mostly-transparent tint
-- -- rectangle, and without it Hyprland renders that as an opaque fallback
-- -- square instead of blurring through it.
-- hl.layer_rule({
--     match = { namespace = "^quickshell:keytree$" },
--     blur = true,
--     ignore_alpha = 0.01,
-- })

-- Quickshell overlay host (quickshell/modules/overlay) - bolts, bar popups,
-- keytree and the other panels. Strikes last ~200-350ms, so the default
-- layersIn fade would eat most of them; everything in it animates itself.
hl.layer_rule({
    match = { namespace = "^quickshell:overlay$" },
    no_anim = true,
})
