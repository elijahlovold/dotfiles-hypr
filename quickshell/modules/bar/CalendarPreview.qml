pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.overlay

// Month-grid popup, right-click-toggled open from Clock.qml. Same pipeline
// as MusicPreview.qml: the calendar grid itself is pure QML/JS (Date math),
// no script needed - only clicking a day to open/create its Obsidian daily
// note shells out, since that's a real filesystem+URI-scheme action.
// (ported/adapted from ilyamiro-quickshell's CalendarPopup.qml, which also
// bundled a weather widget and class-schedule panel - dropped here, out of
// scope for "calendar popup" and not requested.)
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height
    // Floating adds a yearly view (`y`) and an Agenda pane for the hovered
    // day; docked is just the month grid.

    readonly property string dailyNoteScript: "todays-notes"

    readonly property var todayDate: new Date()
    property int monthOffset: 0
    readonly property var displayDate: new Date(popup.todayDate.getFullYear(), popup.todayDate.getMonth() + popup.monthOffset, 1)
    readonly property string iconPrev: String.fromCharCode(0xf104) // fa-angle-left
    readonly property string iconNext: String.fromCharCode(0xf105) // fa-angle-right
    readonly property string iconToday: String.fromCharCode(0xf073) // fa-calendar

    ListModel { id: dayModel }

    // ── Floating extras ──────────────────────────────────────────────────
    property bool yearView: false
    readonly property bool showYear: popup.floating && popup.yearView
    // The day the Agenda pane shows: the one under the mouse, else the
    // keyboard cursor (moving the cursor drops the hover).
    property var hoverDate: null
    readonly property var agendaDate: popup.hoverDate ?? popup.cursor

    function pad2(n) {
        return String(n).padStart(2, "0");
    }

    function isoDate(d) {
        return d.getFullYear() + "-" + popup.pad2(d.getMonth() + 1) + "-" + popup.pad2(d.getDate());
    }

    // Daily notes live at ~/vault/Calendar/<year>/<date>.md (what
    // todays-notes creates). Read directly - todays-notes would create the
    // note for every day the mouse crosses.
    readonly property string agendaPath: popup.floating
        ? Quickshell.env("HOME") + "/vault/Calendar/" + popup.agendaDate.getFullYear() + "/" + popup.isoDate(popup.agendaDate) + ".md"
        : ""
    property var agendaLines: []
    property bool agendaMissing: false

    FileView {
        path: popup.agendaPath
        onLoaded: {
            popup.agendaMissing = false;
            popup.agendaLines = popup.parseAgenda(text());
        }
        onLoadFailed: {
            popup.agendaMissing = true;
            popup.agendaLines = [];
        }
    }

    // Inline markdown -> rich text: [[wikilinks]], [links](url), #tags,
    // **bold**, *italic*, ~~strike~~ and `code`.
    function inlineMd(text) {
        const link = Theme.accent.toString();
        const dim = Theme.dimText.toString();
        return text
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/`([^`]+)`/g, '<code><font color="' + dim + '">$1</font></code>')
            .replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, '<font color="' + link + '">$2</font>')
            .replace(/\[\[([^\]]+)\]\]/g, '<font color="' + link + '">$1</font>')
            .replace(/\[([^\]]+)\]\([^)]*\)/g, '<font color="' + link + '"><u>$1</u></font>')
            .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
            .replace(/(^|[\s(])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>")
            .replace(/~~([^~]+)~~/g, "<s>$1</s>")
            .replace(/(^|\s)#([\w\/-]+)/g, '$1<font color="' + link + '">#$2</font>');
    }

    // The "# Agenda" section of a note (up to the next top-level heading) as
    // [{ depth, kind: bullet|todo|done|skip|text|heading, html }].
    function parseAgenda(raw) {
        const out = [];
        let inside = false;
        for (const rawLine of raw.split("\n")) {
            const line = rawLine.replace(/\t/g, "  ").replace(/\s+$/, "");
            if (/^#\s/.test(line)) {
                if (inside)
                    break;
                inside = /^#\s+agenda\s*$/i.test(line);
                continue;
            }
            if (!inside || line.length === 0)
                continue;
            let m = line.match(/^(\s*)[-*+]\s+\[([ xX-])\]\s+(.*)$/);
            if (m) {
                const mark = m[2];
                out.push({ depth: Math.floor(m[1].length / 2), kind: mark === " " ? "todo" : mark === "-" ? "skip" : "done", html: popup.inlineMd(m[3]) });
                continue;
            }
            m = line.match(/^(\s*)[-*+]\s+(.*)$/);
            if (m) {
                out.push({ depth: Math.floor(m[1].length / 2), kind: "bullet", html: popup.inlineMd(m[2]) });
                continue;
            }
            m = line.match(/^#{2,6}\s+(.*)$/);
            if (m) {
                out.push({ depth: 0, kind: "heading", html: popup.inlineMd(m[1]) });
                continue;
            }
            out.push({ depth: Math.floor((line.length - line.trimStart().length) / 2), kind: "text", html: popup.inlineMd(line.trim()) });
        }
        return out;
    }

    // Keyboard cursor (vim motions): h/l a day, j/k a week, n/p a month,
    // gg/G first/last day of the month, 0 back to today, Enter opens that
    // day's note (same as clicking it). Starts on today;
    // the shown month follows the cursor.
    property var cursor: new Date(popup.todayDate.getFullYear(), popup.todayDate.getMonth(), popup.todayDate.getDate())
    readonly property string cursorKey: popup.dateKey(popup.cursor.getFullYear(), popup.cursor.getMonth(), popup.cursor.getDate())

    function dateKey(year, month, day) {
        return year + "-" + month + "-" + day;
    }

    function moveCursor(days) {
        const c = popup.cursor;
        popup.setCursor(new Date(c.getFullYear(), c.getMonth(), c.getDate() + days));
    }

    function moveMonth(months) {
        const c = popup.cursor;
        // Clamp to the target month's length (Jan 31 + 1 month -> Feb 28).
        const last = new Date(c.getFullYear(), c.getMonth() + months + 1, 0).getDate();
        popup.setCursor(new Date(c.getFullYear(), c.getMonth() + months, Math.min(c.getDate(), last)));
    }

    // Weeks run Sunday-Saturday, matching the grid's rows.
    function weekStart(count) {
        const dow = popup.cursor.getDay();
        popup.moveCursor(-(dow === 0 ? 7 * count : dow + 7 * (count - 1)));
    }

    function weekEnd(count) {
        const dow = popup.cursor.getDay();
        popup.moveCursor(dow === 6 ? 7 * count : 6 - dow + 7 * (count - 1));
    }

    function setCursor(date) {
        popup.hoverDate = null;
        popup.cursor = date;
        popup.monthOffset = (date.getFullYear() - popup.todayDate.getFullYear()) * 12 + date.getMonth() - popup.todayDate.getMonth();
    }

    onVimAction: (name, count) => {
        const c = popup.cursor;
        switch (name) {
        case "left":
            popup.moveCursor(-count);
            break;
        case "right":
            popup.moveCursor(count);
            break;
        case "up":
            popup.moveCursor(-7 * count);
            break;
        case "down":
            popup.moveCursor(7 * count);
            break;
        case "key:b":
            popup.weekStart(count);
            break;
        case "key:e":
            popup.weekEnd(count);
            break;
        case "next":
            popup.moveMonth(popup.showYear ? 12 * count : count);
            break;
        case "prev":
            popup.moveMonth(popup.showYear ? -12 * count : -count);
            break;
        case "key:y":
            if (popup.floating)
                popup.yearView = !popup.yearView;
            break;
        case "top":
            popup.setCursor(new Date(c.getFullYear(), c.getMonth(), 1));
            break;
        case "bottom":
            popup.setCursor(new Date(c.getFullYear(), c.getMonth() + 1, 0));
            break;
        case "zero":
            popup.setCursor(new Date(popup.todayDate.getFullYear(), popup.todayDate.getMonth(), popup.todayDate.getDate()));
            break;
        case "select":
            popup.openDailyNote(c.getFullYear(), c.getMonth(), c.getDate());
            break;
        }
    }

    function rebuildGrid() {
        dayModel.clear();
        const year = popup.displayDate.getFullYear();
        const month = popup.displayDate.getMonth();
        const todayY = popup.todayDate.getFullYear();
        const todayM = popup.todayDate.getMonth();
        const todayD = popup.todayDate.getDate();

        const firstDow = new Date(year, month, 1).getDay(); // 0 = Sunday, already Sunday-first index

        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const daysInPrevMonth = new Date(year, month, 0).getDate();
        const prevMonth = month === 0 ? 11 : month - 1;
        const prevYear = month === 0 ? year - 1 : year;
        const nextMonth = month === 11 ? 0 : month + 1;
        const nextYear = month === 11 ? year + 1 : year;

        for (let i = firstDow - 1; i >= 0; i--) {
            dayModel.append({ day: daysInPrevMonth - i, month: prevMonth, year: prevYear, inMonth: false, isToday: false });
        }
        for (let d = 1; d <= daysInMonth; d++) {
            dayModel.append({ day: d, month: month, year: year, inMonth: true, isToday: year === todayY && month === todayM && d === todayD });
        }
        const remaining = 42 - dayModel.count;
        for (let d = 1; d <= remaining; d++) {
            dayModel.append({ day: d, month: nextMonth, year: nextYear, inMonth: false, isToday: false });
        }
    }

    // Opens in a new terminal in place of the popup (PillPopup.launch), so
    // the terminal takes the keyboard when it maps.
    function openDailyNote(year, month, day) {
        const date = String(year) + "-"
            + String(month + 1).padStart(2, "0") + "-"
            + String(day).padStart(2, "0");
        popup.launch([
            "alacritty", "-e", "sh", "-c", 'nvim "$(todays-notes "$1")"', "sh", date
        ]);
    }

    onDisplayDateChanged: rebuildGrid()
    Component.onCompleted: rebuildGrid()

    Item {
        id: card
        readonly property real mainWidth: popup.showYear ? 3 * (7 * 22) + 2 * 24 : 248
        readonly property real paneWidth: 300
        readonly property real contentHeight: popup.showYear ? yearGrid.implicitHeight : layout.implicitHeight
        width: 32 + card.mainWidth + (popup.floating ? 25 + card.paneWidth : 0)
        height: card.contentHeight + 32

        Column {
            id: layout
            x: 16
            y: 16
            visible: !popup.showYear
            width: card.mainWidth
            spacing: 12

            Row {
                width: parent.width
                height: 24

                Text {
                    id: prevBtn
                    width: 24
                    height: 24
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: popup.iconPrev
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.monthOffset -= 1
                    }
                }
                Item {
                    id: monthLabelWrap
                    width: parent.width - prevBtn.width - nextBtn.width - todayBtn.width
                    height: 24

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: Qt.formatDateTime(popup.displayDate, "MMMM")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                onWheel: wheel => popup.monthOffset += wheel.angleDelta.y > 0 ? 1 : -1
                            }
                        }
                        Text {
                            text: Qt.formatDateTime(popup.displayDate, "yyyy")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                onWheel: wheel => popup.monthOffset += (wheel.angleDelta.y > 0 ? 1 : -1) * 12
                            }
                        }
                    }
                }
                Text {
                    id: todayBtn
                    width: 24
                    height: 24
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: popup.iconToday
                    color: popup.monthOffset === 0 ? Theme.accent : Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.monthOffset = 0
                    }
                }
                Text {
                    id: nextBtn
                    width: 24
                    height: 24
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: popup.iconNext
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.monthOffset += 1
                    }
                }
            }

            Row {
                width: parent.width

                Repeater {
                    model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                    delegate: Text {
                        required property string modelData
                        width: layout.width / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                    }
                }
            }

            Grid {
                width: parent.width
                columns: 7

                Repeater {
                    model: dayModel
                    delegate: Rectangle {
                        id: dayCell
                        required property int day
                        required property int month
                        required property int year
                        required property bool inMonth
                        required property bool isToday
                        readonly property bool isCursor: popup.keyboardActive
                            && popup.cursorKey === popup.dateKey(dayCell.year, dayCell.month, dayCell.day)

                        width: layout.width / 7
                        height: width
                        radius: 6
                        color: dayCell.isToday ? Theme.accent
                             : dayMa.containsMouse ? Theme.pillBorder
                             : "transparent"
                        border.width: dayCell.isCursor ? 2 : 0
                        border.color: dayCell.isToday ? Theme.text : Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: dayCell.day
                            color: dayCell.isToday ? Theme.onAccentText
                                 : dayCell.inMonth ? Theme.text
                                 : Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: dayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: popup.hoverDate = new Date(dayCell.year, dayCell.month, dayCell.day)
                            onClicked: popup.openDailyNote(dayCell.year, dayCell.month, dayCell.day)
                        }
                    }
                }
            }
        }

        // ── Yearly view (floating, `y`): twelve mini months, like `cal 2026`.
        Grid {
            id: yearGrid
            x: 16
            y: 16
            visible: popup.showYear
            columns: 3
            columnSpacing: 24
            rowSpacing: 10

            Repeater {
                model: 12

                delegate: Column {
                    id: mini
                    required property int index
                    readonly property int year: popup.cursor.getFullYear()
                    readonly property int firstDow: new Date(mini.year, mini.index, 1).getDay()
                    readonly property int daysInMonth: new Date(mini.year, mini.index + 1, 0).getDate()
                    spacing: 3

                    Text {
                        text: Qt.formatDate(new Date(mini.year, mini.index, 1), "MMMM") + (mini.index === 0 ? " " + mini.year : "")
                        color: mini.index === popup.cursor.getMonth() ? Theme.accent : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                popup.setCursor(new Date(mini.year, mini.index, 1));
                                popup.yearView = false;
                            }
                        }
                    }

                    Row {
                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]
                            delegate: Text {
                                required property string modelData
                                width: 22
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                color: Theme.dimText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
                                font.bold: true
                            }
                        }
                    }

                    Grid {
                        columns: 7

                        Repeater {
                            model: 42

                            delegate: Rectangle {
                                id: miniDay
                                required property int index
                                readonly property int day: miniDay.index - mini.firstDow + 1
                                readonly property bool valid: miniDay.day >= 1 && miniDay.day <= mini.daysInMonth
                                readonly property bool isToday: miniDay.valid && mini.year === popup.todayDate.getFullYear()
                                    && mini.index === popup.todayDate.getMonth() && miniDay.day === popup.todayDate.getDate()
                                readonly property bool isCursor: miniDay.valid && popup.keyboardActive
                                    && popup.cursorKey === popup.dateKey(mini.year, mini.index, miniDay.day)

                                width: 22
                                height: 22
                                radius: 4
                                color: miniDay.isToday ? Theme.accent
                                     : miniMa.containsMouse && miniDay.valid ? Theme.pillBorder
                                     : "transparent"
                                border.width: miniDay.isCursor ? 2 : 0
                                border.color: miniDay.isToday ? Theme.text : Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    visible: miniDay.valid
                                    text: miniDay.day
                                    color: miniDay.isToday ? Theme.onAccentText : Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                }

                                MouseArea {
                                    id: miniMa
                                    anchors.fill: parent
                                    enabled: miniDay.valid
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: popup.hoverDate = new Date(mini.year, mini.index, miniDay.day)
                                    onClicked: popup.openDailyNote(mini.year, mini.index, miniDay.day)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Agenda pane (floating): the "# Agenda" section of the day's note.
        Rectangle {
            visible: popup.floating
            x: 16 + card.mainWidth + 12
            y: 16
            width: 1
            height: card.contentHeight
            color: Theme.pillBorder
        }

        Item {
            id: agendaPane
            visible: popup.floating
            x: 16 + card.mainWidth + 25
            y: 16
            width: card.paneWidth
            height: card.contentHeight

            Column {
                id: agendaHead
                width: parent.width
                spacing: 2

                Text {
                    text: "Agenda"
                    color: Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                }
                Text {
                    text: Qt.formatDate(popup.agendaDate, "dddd, MMMM d")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
            }

            Text {
                visible: popup.agendaLines.length === 0
                anchors.top: agendaHead.bottom
                anchors.topMargin: 14
                text: popup.agendaMissing ? "No note for this day" : "Nothing in the agenda"
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                font.italic: true
            }

            Flickable {
                anchors.top: agendaHead.bottom
                anchors.topMargin: 12
                anchors.bottom: parent.bottom
                width: parent.width
                contentHeight: agendaList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: agendaList
                    width: parent.width
                    spacing: 5

                    Repeater {
                        model: popup.agendaLines

                        delegate: Row {
                            id: agendaRow
                            required property var modelData
                            readonly property bool finished: modelData.kind === "done" || modelData.kind === "skip"
                            readonly property bool isCheck: modelData.kind === "todo" || finished
                            spacing: 7
                            leftPadding: modelData.depth * 16
                            width: agendaList.width

                            // Bullet dot / checkbox.
                            Item {
                                visible: agendaRow.modelData.kind !== "text" && agendaRow.modelData.kind !== "heading"
                                width: 14
                                height: 18

                                Rectangle {
                                    visible: !agendaRow.isCheck
                                    anchors.centerIn: parent
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: Theme.dimText
                                }
                                Rectangle {
                                    visible: agendaRow.isCheck
                                    anchors.centerIn: parent
                                    width: 13
                                    height: 13
                                    radius: 3
                                    color: agendaRow.modelData.kind === "done" ? Theme.accent : "transparent"
                                    border.width: 1
                                    border.color: agendaRow.modelData.kind === "todo" ? Theme.text : Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: agendaRow.modelData.kind === "done" ? "✓" : agendaRow.modelData.kind === "skip" ? "–" : ""
                                        color: agendaRow.modelData.kind === "done" ? Theme.onAccentText : Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }
                            }

                            Text {
                                width: agendaRow.width - agendaRow.leftPadding - (agendaRow.modelData.kind === "text" || agendaRow.modelData.kind === "heading" ? 0 : 21)
                                textFormat: Text.RichText
                                wrapMode: Text.Wrap
                                text: agendaRow.finished ? "<s>" + agendaRow.modelData.html + "</s>" : agendaRow.modelData.html
                                color: agendaRow.finished ? Theme.dimText : agendaRow.modelData.kind === "heading" ? Theme.dimText : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: agendaRow.modelData.kind === "heading"
                            }
                        }
                    }
                }
            }
        }
    }
}
