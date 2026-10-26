pragma ComponentBehavior: Bound
import QtQuick
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

    readonly property string dailyNoteScript: "todays-notes"

    readonly property var todayDate: new Date()
    property int monthOffset: 0
    readonly property var displayDate: new Date(popup.todayDate.getFullYear(), popup.todayDate.getMonth() + popup.monthOffset, 1)
    readonly property string iconPrev: String.fromCharCode(0xf104) // fa-angle-left
    readonly property string iconNext: String.fromCharCode(0xf105) // fa-angle-right
    readonly property string iconToday: String.fromCharCode(0xf073) // fa-calendar

    ListModel { id: dayModel }

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
            popup.moveMonth(count);
            break;
        case "prev":
            popup.moveMonth(-count);
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
        width: 280
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
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
                            onClicked: popup.openDailyNote(dayCell.year, dayCell.month, dayCell.day)
                        }
                    }
                }
            }
        }
    }
}
