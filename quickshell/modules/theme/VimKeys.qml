import QtQuick

// Small vim-style key parser shared by every PillPopup. Turns raw key
// events into named actions so each popup only maps actions to behaviour:
//
//   j / k / h / l (and arrows)  down / up / left / right
//   gg / G                      top / bottom
//   n / p                       next / prev
//   Return / Enter              select
//   Space                       space
//   Escape                      escape
//   0 (not part of a count)     zero
//   any other single letter     "key:<letter>"  (e.g. "key:r")
//
// A numeric prefix becomes the count (`5j` -> down, 5). Pending state
// (a lone `g`, a half-typed count) expires after a short pause, like vim's
// timeoutlen.
QtObject {
    id: vim

    property string pending: ""
    property string countText: ""

    signal action(string name, int count)

    readonly property var letters: ({
        j: "down",
        k: "up",
        h: "left",
        l: "right",
        G: "bottom",
        n: "next",
        p: "prev"
    })

    property Timer timeout: Timer {
        interval: 800
        onTriggered: {
            vim.pending = "";
            vim.countText = "";
        }
    }

    // Returns whether the event was consumed.
    function feed(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;

        let name = "";
        switch (event.key) {
        case Qt.Key_Escape:
            name = "escape";
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            name = "select";
            break;
        case Qt.Key_Space:
            name = "space";
            break;
        case Qt.Key_Down:
            name = "down";
            break;
        case Qt.Key_Up:
            name = "up";
            break;
        case Qt.Key_Left:
            name = "left";
            break;
        case Qt.Key_Right:
            name = "right";
            break;
        }

        if (name.length === 0) {
            const text = event.text;
            if (/^[1-9]$/.test(text) || (text === "0" && vim.countText.length > 0)) {
                vim.countText += text;
                vim.timeout.restart();
                return true;
            }
            if (text === "0") {
                name = "zero";
            } else if (text === "g") {
                if (vim.pending !== "g") {
                    vim.pending = "g";
                    vim.timeout.restart();
                    return true;
                }
                name = "top";
            } else if (vim.letters[text] !== undefined) {
                name = vim.letters[text];
            } else if (/^[A-Za-z]$/.test(text)) {
                name = "key:" + text;
            }
        }

        const count = parseInt(vim.countText) || 1;
        vim.pending = "";
        vim.countText = "";
        vim.timeout.stop();
        if (name.length === 0)
            return false;
        vim.action(name, count);
        return true;
    }
}
