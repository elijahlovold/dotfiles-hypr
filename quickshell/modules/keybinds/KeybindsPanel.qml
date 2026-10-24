pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.overlay

// A modal OverlaySurface (modules/overlay) centered on the focused screen,
// like KeytreePanel.qml / ImagePickerPanel.qml. Hosts a KeybindService
// instance (fetches `hyprctl binds -j` once on open) plus shared filter
// state (submap/modifier), read by KeyboardGrid.
OverlaySurface {
    id: root

    modal: true
    inputItem: contentItem
    z: 1

    KeybindService {
        id: service
    }

    // Per-mod filter state: "include" (must have it), "exclude" (must not
    // have it, set via right-click), or absent/"" (don't care).
    property var modFilters: ({})
    property string activeSubmap: ""

    // Left click sets/clears "include"; right click sets/clears "exclude".
    // Either always overwrites the other (a mod can't be both at once).
    function setModFilter(m, mode) {
        const current = root.modFilters[m] || "";
        const updated = Object.assign({}, root.modFilters);
        if (current === mode)
            delete updated[m];
        else
            updated[m] = mode;
        root.modFilters = updated;
    }

    Item {
        id: contentItem
        anchors.centerIn: parent
        width: Math.min(920, (root.screen?.width ?? 0) - 80)
        height: Math.min(700, (root.screen?.height ?? 0) - 80)
        focus: true

        // Closing is Escape, the X button, or a click off the panel.
        // Everything else gets routed to the grid's own key-selection /
        // list-navigation handling.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.dismissed();
                event.accepted = true;
                return;
            }
            if (keyboardGrid.handleKeyEvent(event))
                event.accepted = true;
        }

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Theme.pillBg
            border.width: 1
            border.color: Theme.pillBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ── Header ──────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "Keybinds"
                        color: Theme.text
                        font.pixelSize: 16
                        font.bold: true
                        font.family: Theme.fontFamily
                    }

                    Text {
                        text: keyboardGrid.visibleCount + " bindings"
                        color: Theme.dimText
                        font.pixelSize: 11
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 12
                        color: Theme.hoverBg
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: Theme.dimText
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismissed()
                        }
                    }
                }

                // ── Filters ─────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    // Submap / mode chips
                    Row {
                        spacing: 4
                        Rectangle {
                            width: modeLabel0.implicitWidth + 14
                            height: 22
                            radius: 6
                            color: root.activeSubmap === "" ? Theme.withAlpha(Theme.accent, 0.5) : Theme.hoverBg
                            border.width: 1
                            border.color: Theme.pillBorder
                            Text {
                                id: modeLabel0
                                anchors.centerIn: parent
                                text: "Global"
                                color: Theme.text
                                font.pixelSize: 11
                                font.family: Theme.fontFamily
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeSubmap = ""
                            }
                        }
                        Repeater {
                            model: service.submapNames
                            delegate: Rectangle {
                                id: modeChip
                                required property string modelData
                                width: modeLabel.implicitWidth + 14
                                height: 22
                                radius: 6
                                color: root.activeSubmap === modelData ? Theme.withAlpha(Theme.accent, 0.5) : Theme.hoverBg
                                border.width: 1
                                border.color: Theme.pillBorder
                                Text {
                                    id: modeLabel
                                    anchors.centerIn: parent
                                    text: modeChip.modelData
                                    color: Theme.text
                                    font.pixelSize: 11
                                    font.family: Theme.fontFamily
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.activeSubmap = modeChip.modelData
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 18
                        color: Theme.pillBorder
                    }

                    // Modifier layer chips (a bind matches if it contains
                    // every "include" mod and none of the "exclude" ones -
                    // see setModFilter above and KeyboardGrid.visibleBinds,
                    // the one place that filter predicate actually lives).
                    // Left click toggles include, right click toggles exclude.
                    Row {
                        spacing: 4
                        Repeater {
                            model: ["Super", "Ctrl", "Shift", "Alt"]
                            delegate: Rectangle {
                                id: modChip
                                required property string modelData
                                readonly property string state: root.modFilters[modelData] || ""
                                width: modLabel.implicitWidth + 14
                                height: 22
                                radius: 6
                                color: state === "include" ? Theme.withAlpha(Theme.accent, 0.5) : state === "exclude" ? Theme.withAlpha(Theme.urgentWorkspace, 0.5) : Theme.hoverBg
                                border.width: 1
                                border.color: Theme.pillBorder
                                Text {
                                    id: modLabel
                                    anchors.centerIn: parent
                                    text: (modChip.state === "exclude" ? "¬" : "") + modChip.modelData
                                    color: Theme.text
                                    font.pixelSize: 11
                                    font.family: Theme.fontFamily
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => root.setModFilter(modChip.modelData, mouse.button === Qt.RightButton ? "exclude" : "include")
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                // ── Content ─────────────────────────────────────────────
                KeyboardGrid {
                    id: keyboardGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    service: service
                    modFilters: root.modFilters
                    activeSubmap: root.activeSubmap
                    onOpenedInEditor: root.dismissed()
                }
            }
        }
    }
}
