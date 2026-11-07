pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// Syncthing connection + sync glyphs (what scripts/syncthing-status.sh used
// to print), homelab services up/total (Portainer) and a tailscale glyph,
// state in HomelabState.qml. Hover or right-click opens HomelabPreview
// docked, left-click opens it floating.
Item {
    id: root

    readonly property string iconServer: "󰒋"
    readonly property string iconTailscale: "󰖂"
    readonly property bool tsUp: HomelabState.tsState === "Running"
    property bool previewOpen: false

    implicitWidth: row.width
    implicitHeight: row.height
    width: implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: 10

        Text {
            visible: HomelabState.stConfigured
            text: (HomelabState.stConnected ? "󰌹" : "󰌺")
                  + (HomelabState.stSync === "synced" ? " 󰄬"
                     : HomelabState.stSync === "almost" ? " 󰁝"
                     : HomelabState.stSync === "syncing" ? " 󰓦" : "")
            color: HomelabState.stReachable ? Theme.text : Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        // Tailscale is always shown, so each separator only needs the
        // component to its left.
        Separator { visible: HomelabState.stConfigured }

        Text {
            visible: HomelabState.configured
            text: root.iconServer + "  " + (HomelabState.servicesError.length > 0 && HomelabState.totalCount === 0
                    ? "?" : HomelabState.upCount + "/" + HomelabState.totalCount)
            color: HomelabState.upCount < HomelabState.totalCount || HomelabState.servicesError.length > 0
                   ? "#ff4d4d" : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Separator { visible: HomelabState.configured }

        Text {
            text: root.iconTailscale
            color: root.tsUp ? Theme.text : Theme.dimText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onPositionChanged: mouse => opener.hoverMoved(mapToItem(null, mouse.x, mouse.y))
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                opener.toggle();
            else
                opener.toggleFloating();
        }
    }

    PopupOpener {
        id: opener
        widget: root
        name: "homelab"
        popup: HomelabPreview {
            anchorItem: root
        }
    }
}
