pragma Singleton
import QtQuick
import Quickshell

// QML port of ~/.config/keytree/config.toml's [commands]/[layout]/[keys.*].
// Colors live in qs.modules.theme's Theme singleton instead (wallust-
// overridable, see modules/theme/Theme.qml). Editing the tree/layout here
// is the equivalent of editing the TOML.
Singleton {
    id: root

    readonly property var keybindings: ({
        back: "Escape",
        quit: "q",
        search: "/"
    })

    readonly property var layout: ({
        // ring - nodes on one/two rings around a hub, joined by spokes
        // hex  - honeycomb tiles growing ring by ring around a hub tile
        // hang - nodes dropping from the top edge on strings (spoke style)
        // tree - a tree growing from the bottom edge; folders branch on
        type: "ring",
        ringThreshold: 12,
        // Single knobs instead of hand-tuning many pixel constants:
        // ringScale multiplies the popup's overall window/ring-radius size;
        // nodeScale multiplies the node circle size independently of
        // ring spacing; fontScale multiplies every text size in both the
        // radial and search views. 1.0 = the original tuned-by-hand look
        // for each. If nodeScale grows much past ringScale, cards will
        // start crowding the outer ring - bump ringScale too if so.
        ringScale: 1.2,
        nodeScale: 1.6,
        fontScale: 1.2,

        // Per-layout knobs, px unless noted.
        hex: ({
            tileSize: 62,          // center to corner
            gap: 15,               // between tile edges
            ringDelay: 40          // ms between rings growing in
        }),
        hang: ({
            length: 190,           // shortest string
            centerDrop: 150,       // extra length toward the middle
            swing: 0.16,           // rad, sway after landing
            bounce: 0.55           // 0-1, spring when the string catches
        }),
        tree: ({
            trunk: 210,            // trunk height
            canopy: 420,           // starting canopy size (grows to fit)
            thickness: 3.5,        // branch weight
            fork: 0.42,            // 0-1, how far toward its leaves a branch forks
            foliage: true          // leaf sprigs on the finer branches
        })
    })

    // Connectors from the center to the nodes. Each style is
    // spokes/<Name>.qml - see spokes/SpokeStyle.qml to add one.
    readonly property var spokes: ({
        // radial  - straight lines (the original look)
        // laced   - bicycle-wheel cross lacing, two spokes per node
        // galaxy  - logarithmic spiral arms with a trailing dust lane
        // vortex  - arms winding most of a turn into each node
        // truss   - crane-boom lattice, two chords + zigzag web
        // helix   - twisting DNA strands with rungs (animated, GPU shader)
        // tesla   - flickering glowing discharge arcs (animated, GPU shader)
        style: "laced",
        tone: "connector",         // any Theme color property, e.g. "centerDot"
        opacity: 0.8,
        lineWidth: 1.5,
        gap: 4,                    // px kept clear around the hub and nodes
        hub: "ring"                // root center: "ring" (empty node-sized circle) or "dot"
    })

    readonly property var trees: ({
      "default": {
        "i": { icon: "  ", label: "Iriun",    cmd: "iriunwebcam" },
        "k": { icon: "  ", label: "Bible",    cmd: "alacritty -e nvim ~/dox/bible_kjv.txt" },
        "l": { icon: "  ", label: "Download", cmd: "xdg-open \"$HOME/dl/$(ls -t $HOME/dl | head -n 1)\"" },
        "c": { icon: "󰄛  ", label: "C&H",      cmd: "mupdf -r 180 ~/dox/books/The\\ Complete\\ Calvin\\ \\&\\ Hobbes.pdf $((1 + RANDOM % 1350))" },
        "o": { icon: "  ", label: "Obsidian", cmd: "obsidian \"obsidian://open?vault=vault\"" , shift_cmd: "obsidian \"obsidian://open?vault=Shared-Vault\"" },
        "p": { icon: "  ", label: "Python",   cmd: "alacritty -e python3.14" },
        "t": { icon: "󰄛  ", label: "Kitty",    cmd: "kitty" },
        "z": { icon: "󰈙  ", label: "Zathura",  cmd: "zathura" },
        "b": {
          label: "Bookmarks/",
          icon: "  ",
          children: {
            "c": { icon: "  ", label: "Calendar",   cmd: "firefox --new-window https://calendar.google.com/calendar/u/0/r" },
            "d": { icon: "󰺄  ", label: "Dictionary", cmd: "firefox --new-window https://www.dictionary.com/" },
            "g": { icon: "󰊤  ", label: "Github",     cmd: "firefox --new-window https://github.com/elijahlovold?tab=repositories" },
            "l": { icon: "󰌻  ", label: "Linkedin",   cmd: "firefox --new-window https://www.linkedin.com/feed/" },
            "m": { icon: "󰇮  ", label: "Mail",       cmd: "firefox --new-window https://mail.google.com/mail/u/0/#inbox" },
            "n": { icon: "󰼭  ", label: "Monkeytype", cmd: "firefox --new-window https://monkeytype.com/" },
            "t": { icon: "󰧑  ", label: "ChatGPT",    cmd: "firefox --new-window https://chatgpt.com/" },
            "w": { icon: "󰖬  ", label: "Wikipedia",  cmd: "firefox --new-window https://www.wikipedia.org/" },
            "y": { icon: "󰗃  ", label: "Youtube",    cmd: "firefox --new-window https://youtube.com/" },
          }
        },
        "d": {
          label: "Design/",
          icon: "   ",
          children: {
            "a": { icon: "  ", label: "Android", cmd: "android-studio" },
            "t": { icon: "Q  ", label: "Qt Designer", cmd: "designer6" },
            "b": { icon: "  ", label: "Blender", cmd: "blender" },
            "g": { icon: "  ", label: "Godot",   cmd: "godot" },
            "i": { icon: "  ", label: "Gimp",    cmd: "gimp" },
            "l": { icon: "󰐋  ", label: "LTSpice", cmd: "ltspice" },
            "o": { icon: "  ", label: "OBS",     cmd: "obs" },
            "s": { icon: "󱑽  ", label: "Logic 2", cmd: "saleae-logic2" },
            "u": { icon: "󰹛  ", label: "Bambu",   cmd: "bambu-studio" },
          }
        },
        "e": {
          label: "EE/",
          icon: "  ",
          children: {
            "d": { icon: "󰬋  ", label: "Digikey",  cmd: "firefox --new-window https://www.digikey.com/" },
            "e": { icon: "󰬰  ", label: "EDN",      cmd: "firefox --new-window https://www.edn.com/" },
            "n": { icon: "󰎖  ", label: "Nordic",   cmd: "firefox --new-window https://devzone.nordicsemi.com/" },
            "o": { icon: "  ", label: "Octopart", cmd: "firefox --new-window https://octopart.com/" },
          }
        },
        "f": {
          label: "Config",
          icon: "  ",
          children: {
            "a": { icon: "󱍵  ", label: "Aliases",   cmd: "alacritty -e nvim +'cd ~/.config/' ~/.config/aliases" },
            "b": { icon: "  ", label: "Btop",      cmd: "alacritty -e nvim +'cd ~/.config/btop/' ~/.config/btop/btop.conf" },
            "c": { icon: "󰧑  ", label: "cl-wrap",   cmd: "alacritty -e nvim +'cd ~/.config/scripts/' ~/.config/scripts/cl-wrap" },
            "e": { icon: "󰇧  ", label: "Env",       cmd: "alacritty -e nvim +'cd ~/.config/' ~/.config/env" },
            "h": { icon: "󱇙  ", label: "Hypr",      cmd: "alacritty -e nvim +'cd ~/.config/hypr/' ~/.config/hypr/" },
            "i": { icon: "󱇙  ", label: "i3wm",      cmd: "alacritty -e nvim +'cd ~/.config/i3/' ~/.config/i3/config" },
            "k": { icon: "  ", label: "Keytree",   cmd: "alacritty -e nvim +'cd ~/.config/quickshell/modules/keytree/' ~/.config/quickshell/modules/keytree/KeytreeConfig.qml", shift_cmd: "alacritty -e nvim +'cd ~/.config/keytree/' ~/.config/keytree/config.toml" },
            "l": { icon: "🅰  ", label: "Alacritty", cmd: "alacritty -e nvim +'cd ~/.config/alacritty/' ~/.config/alacritty/alacritty.toml" },
            "m": { icon: "󰣆  ", label: "Mimes",     cmd: "alacritty -e nvim +'cd ~/.config/' ~/.config/mimeapps.list" },
            "n": { icon: "  ", label: "Nvim",      cmd: "alacritty -e nvim +'cd ~/.config/nvim/lua/' ~/.config/nvim/lua/" },
            "p": { icon: "  ", label: "Picom",     cmd: "alacritty -e nvim +'cd ~/.config/picom/' ~/.config/picom/picom.conf" },
            "s": { icon: "  ", label: "i3 Status", cmd: "alacritty -e nvim +'cd ~/.config/i3status-rust/' ~/.config/i3status-rust/config.toml" },
            "u": { icon: "  ", label: "Qksh",      cmd: "alacritty -e nvim +'cd ~/.config/quickshell/' ~/.config/quickshell/" },
            "w": { icon: "󰏘  ", label: "Wallust",   cmd: "alacritty -e nvim +'cd ~/.config/wallust/' ~/.config/wallust/wallust.toml" },
            "z": { icon: "󰏘  ", label: "zsh",       cmd: "alacritty -e nvim +'cd ~/.config/zsh/' ~/.config/zsh/.zshrc" },
          }
        },
        "g": {
          label: "Games/",
          icon: "  ",
          children: {
            "a": { icon: "󰓥  ", label: "AoE2",          cmd: "steam -applaunch 813780" },
            "f": { icon: "  ", label: "Factorio",      cmd: "steam -applaunch 427520" },
            "h": { icon: "󰷟  ", label: "Hollow Knight", cmd: "steam -applaunch 4183110" },
            "j": { icon: "󰓎  ", label: "Just Cause 2",  cmd: "steam -applaunch 8190" },
            "k": { icon: "󱇫  ", label: "Silksong",      cmd: "steam -applaunch 1030300" },
            "m": { icon: "󰍳  ", label: "Minecraft",     cmd: "mcpelauncher-ui-qt" },
            "r": { icon: "󰰞  ", label: "R2ModMan",      cmd: "r2modman" },
            "s": { icon: "  ", label: "Steam",         cmd: "steam" },
            "t": { icon: "󰔱  ", label: "Terraria",      cmd: "steam -applaunch 105600" },
            "v": { icon: "󰷚  ", label: "Vim-Sweeper",   cmd: "alacritty -e vim-sweeper" },
          }
        },
        "h": {
          label: "Work/",
          icon: "󰸖  ",
          children: {
            "b": { icon: "  ", label: "Bitbucket", cmd: "google-chrome https://bitbucket.org/cadenceneuro/workspace/overview/" },
            "c": { icon: "  ", label: "Calendar",  cmd: "google-chrome https://calendar.google.com/calendar/u/0/r" },
            "d": { icon: "  ", label: "Drive",     cmd: "google-chrome https://drive.google.com/drive/home" },
            "j": { icon: "  ", label: "Jira",      cmd: "google-chrome https://cadenceneuro.atlassian.net/issues?filter=11558" },
            "m": { icon: "󰇮  ", label: "Mail",      cmd: "google-chrome https://mail.google.com/mail/u/0/#inbox" },
            "o": { icon: "  ", label: "Obsidian",  cmd: "obsidian \"obsidian://open?vault=Shared-Vault\"" },
            "w": { icon: "󰧑  ", label: "Wiki",      cmd: "google-chrome https://sites.google.com/cadenceneuro.com/team/home?pli=1" },
          }
        },
        "s": {
          label: "Social/",
          icon: "  ",
          children: {
            "d": { icon: "  ", label: "Discord", cmd: "vesktop", shift_cmd: "discord" },
            "g": { icon: "󰘊  ", label: "Signal",  cmd: "signal-desktop" },
            "n": { icon: "󰿌  ", label: "Session", cmd: "session-desktop" },
            "p": { icon: "  ", label: "Phone",   cmd: "firefox --new-window https://messages.google.com/web/conversations" },
            "s": { icon: "󰒱  ", label: "Slack",   cmd: "slack" },
          }
        },
        "v": {
          label: "Services/",
          icon: "  ",
          children: {
            "o": { icon: "󱑽  ", label: "O-Scope",   cmd: "firefox http://10.11.13.220" },
            "b": { icon: "󰁯  ", label: "Backrest",  cmd: "firefox http://localhost:9898/" },
            "i": { icon: "  ", label: "Immich",    cmd: "firefox https://immich.elovold.xyz" },
            "j": { icon: "󰿎  ", label: "Jellyfin",  cmd: "firefox https://jellyfin.elovold.xyz" },
            "p": { icon: "󰡨  ", label: "Portainer", cmd: "firefox https://edel:9443/" },
            "s": { icon: "  ", label: "Stirling",  cmd: "firefox http://edel:8080/" },
            "t": { icon: "󰖂  ", label: "TailScale", cmd: "firefox https://login.tailscale.com/" },
          }
        },
      },

      // -~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~

      // Super+P - open a bar popup from the keyboard (lightning-strike
      // reveal, see modules/common/BarPopups.qml + modules/bolt).
      "popups": {
        "b": { icon: "  ", label: "Bambu",          cmd: "qs ipc call barpopup float bambu", shift_cmd: "qs ipc call barpopup open bambu" },
        "c": { icon: "  ", label: "Calendar",       cmd: "qs ipc call barpopup float calendar", shift_cmd: "qs ipc call barpopup open calendar" },
        "d": { icon: "  ", label: "Drives",         cmd: "qs ipc call barpopup float drives", shift_cmd: "qs ipc call barpopup open drives" },
        "e": { icon: "  ", label: "Serial",         cmd: "qs ipc call barpopup float serial", shift_cmd: "qs ipc call barpopup open serial" },
        "h": { icon: "  ", label: "System monitor", cmd: "qs ipc call barpopup float sysmon", shift_cmd: "qs ipc call barpopup open sysmon" },
        "i": { icon: "  ", label: "Wi-Fi",          cmd: "qs ipc call barpopup float wifi", shift_cmd: "qs ipc call barpopup open wifi" },
        "m": { icon: "  ", label: "Music",          cmd: "qs ipc call barpopup float music", shift_cmd: "qs ipc call barpopup open music" },
        "n": { icon: "  ", label: "Notifications",  cmd: "qs ipc call barpopup float notifications", shift_cmd: "qs ipc call barpopup open notifications" },
        "p": { icon: "  ", label: "Color picker",   cmd: "qs ipc call barpopup float colorpicker", shift_cmd: "qs ipc call barpopup open colorpicker" },
        "r": { icon: "  ", label: "Record",         cmd: "qs ipc call barpopup float screenrec", shift_cmd: "qs ipc call barpopup open screenrec" },
        "s": { icon: "  ", label: "Sound",          cmd: "qs ipc call barpopup float sound", shift_cmd: "qs ipc call barpopup open sound" },
        "t": { icon: "  ", label: "Theme",          cmd: "qs ipc call barpopup float theme", shift_cmd: "qs ipc call barpopup open theme" },
        "u": { icon: "  ", label: "Unit tools",     cmd: "qs ipc call barpopup float unittools", shift_cmd: "qs ipc call barpopup open unittools" },
        "y": { icon: "󱇯  ", label: "Stator"        , cmd: "qs ipc call barpopup float stator", shift_cmd: "qs ipc call barpopup open stator" },
        "g": { icon: "󰵸  ", label: "GIF maker"     , cmd: "qs ipc call gif toggle" },
        "w": { icon: "󰸉  ", label: "Wallpaper"     , cmd: "qs ipc call imagepicker toggle" },
        // Move every window on the current workspace to the picked one.
        "v": {
          label: "mv-win/",
          icon: "󰍹  ",
          children: {
            "1": { icon: "󰍹  ", label: "Workspace 1",  cmd: "hypr-mv-windows 1" },
            "2": { icon: "󰍹  ", label: "Workspace 2",  cmd: "hypr-mv-windows 2" },
            "3": { icon: "󰍹  ", label: "Workspace 3",  cmd: "hypr-mv-windows 3" },
            "4": { icon: "󰍹  ", label: "Workspace 4",  cmd: "hypr-mv-windows 4" },
            "5": { icon: "󰍹  ", label: "Workspace 5",  cmd: "hypr-mv-windows 5" },
            "6": { icon: "󰍹  ", label: "Workspace 6",  cmd: "hypr-mv-windows 6" },
            "7": { icon: "󰍹  ", label: "Workspace 7",  cmd: "hypr-mv-windows 7" },
            "8": { icon: "󰍹  ", label: "Workspace 8",  cmd: "hypr-mv-windows 8" },
            "9": { icon: "󰍹  ", label: "Workspace 9",  cmd: "hypr-mv-windows 9" },
            "0": { icon: "󰍹  ", label: "Workspace 10", cmd: "hypr-mv-windows 10" },
          }
        },
        // Blank all monitors until the next input (modules/screens).
        "o": { icon: "󰶐  ", label: "Screens off", cmd: "qs ipc call screens off" },
        // Hyprland screen shaders (scripts/hypr-shader, hypr/shaders/).
        // Picking the active one again turns it off; ▶ = animated, which
        // redraws the whole monitor every frame while it's on.
        "f": {
          label: "Shaders/",
          icon: "  ",
          children: {
            "o": { icon: "  ", label: "Off",          cmd: "hypr-shader off" },
            "n": { icon: "  ", label: "Negative",     cmd: "hypr-shader negative" },
            "t": { icon: "  ", label: "TFT",          cmd: "hypr-shader tft" },
            "c": { icon: "  ", label: "CRT",          cmd: "hypr-shader crt" },
            "b": { icon: "  ", label: "Better CRT",   cmd: "hypr-shader bettercrt" },
            "l": { icon: "  ", label: "Bloom",        cmd: "hypr-shader bloom" },
            "g": { icon: "  ", label: "Glitch ▶",     cmd: "hypr-shader glitchy" },
            "w": { icon: "  ", label: "Water ▶",      cmd: "hypr-shader water" },
            "z": { icon: "  ", label: "Drunk ▶",      cmd: "hypr-shader drunkard" },
            "s": { icon: "  ", label: "Snow ▶",       cmd: "hypr-shader just-snow" },
            "r": { icon: "󰖖  ", label: "Rain ▶",       cmd: "hypr-shader rain" },
            "d": { icon: "  ", label: "Raindrops ▶",  cmd: "hypr-shader rain-glass" },
            "e": { icon: "󰖓  ", label: "Lightning ▶",  cmd: "hypr-shader lightning" },
            "m": { icon: "󰙾  ", label: "Storm ▶",      cmd: "hypr-shader storm" },
            "h": { icon: "󱣖  ", label: "Heat ▶",       cmd: "hypr-shader heat" },
            "a": { icon: "󱝁  ", label: "Starfield ▶",  cmd: "hypr-shader starfield" },
            "k": { icon: "󰸰  ", label: "Fireworks ▶",  cmd: "hypr-shader fireworks" },
            "p": { icon: "󰻝  ", label: "Sparks ▶",     cmd: "hypr-shader sparks-from-fire" },
            "f": { icon: "󰈸  ", label: "Sparks + Heat ▶", cmd: "hypr-shader sparks-heat" },
            "x": { icon: "󰘨  ", label: "Matrix ▶",     cmd: "hypr-shader matrix-hallway" },
          }
        },
        // Wallpaper transition effect for the next switches (quickshell-wall
        // WallConfig.effects). Held until WallConfig.effect is edited.
        "x": {
          label: "Transitions/",
          icon: "  ",
          children: {
            "s": { icon: "  ", label: "Shatter",  cmd: "qs -p ~/.config/dotfiles-hypr/quickshell-wall ipc call wallpaper effect shatter" },
            "d": { icon: "  ", label: "Dissolve", cmd: "qs -p ~/.config/dotfiles-hypr/quickshell-wall ipc call wallpaper effect dissolve" },
            "o": { icon: "󰯃  ", label: "Scroll",   cmd: "qs -p ~/.config/dotfiles-hypr/quickshell-wall ipc call wallpaper effect scroll" },
            "i": { icon: "󱑹  ", label: "Ripple",   cmd: "qs -p ~/.config/dotfiles-hypr/quickshell-wall ipc call wallpaper effect ripple" },
            "b": { icon: "  ", label: "Blinds",   cmd: "qs -p ~/.config/dotfiles-hypr/quickshell-wall ipc call wallpaper effect blinds" },
            "p": { icon: "  ", label: "Pixelate", cmd: "qs -p ~/.config/dotfiles-hypr/quickshell-wall ipc call wallpaper effect pixelate" },
            "f": { icon: "  ", label: "Fade",     cmd: "qs -p ~/.config/dotfiles-hypr/quickshell-wall ipc call wallpaper effect fade" },
            "r": { icon: "  ", label: "Random",   cmd: "qs -p ~/.config/dotfiles-hypr/quickshell-wall ipc call wallpaper effect random" },
          }
        },
      },

      // -~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~

      "stator": {
        "b": { icon: "󱎫  ", label: "Break",      cmd: "stator-rs --set-state break" },
        "c": { icon: "  ", label: "Chillin",    cmd: "stator-rs --set-state chill" },
        "d": { icon: "  ", label: "Dist",       cmd: "alacritty -e zsh -c 'stator-rs --dist; exec sh'" },
        "i": { icon: "󰦖  ", label: "Idle",       cmd: "stator-rs --set-state idle" },
        "l": { icon: "  ", label: "Logs",       cmd: "alacritty -e zsh -c 'stator-rs --log; exec sh'" },
        "p": { icon: "  ", label: "Projects",   cmd: "stator-rs --set-state proj" },
        "r": { icon: "  ", label: "Read/Write", cmd: "stator-rs --set-state rw" },
        "w": { icon: "󰦑  ", label: "Work",       cmd: "stator-rs --set-state work" },
      }
    })
}
