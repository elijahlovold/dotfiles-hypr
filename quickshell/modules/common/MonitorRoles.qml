pragma Singleton
import QtQuick
import Quickshell

// Which output plays which role, by orientation rather than name - outputs
// are only named in hypr/hyprland/monitors.lua. A screen's geometry is
// already rotated by its transform, so portrait is just taller than wide.
// Landscape screens are primary (full bar, desktop/reticle/draw overlays,
// notifications); portrait ones are secondary, unless there's no landscape
// screen at all, in which case the first screen is primary regardless.
// Plain property reads, so bindings using these re-evaluate on a hotplug or
// rotation with nothing polled.
Singleton {
    function isPortrait(screen) {
        return !!screen && screen.height > screen.width;
    }

    function isSecondary(screen) {
        return screen !== primaryScreen() && isPortrait(screen);
    }

    function primaryScreen() {
        return Quickshell.screens.find(s => !isPortrait(s)) ?? Quickshell.screens[0];
    }
}
