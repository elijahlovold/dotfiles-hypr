import QtQuick

// Bar widgets kept off the bar: never drawn and taking no space, but their
// popups stay reachable from the keytree / `qs ipc call barpopup open
// <name>`. They live inside the bar window because a popup finds its
// screen through its widget's window. BarPopups.summon() spots the
// `offBar` marker and always opens these floating, since there's no pill
// to hang a docked popup from.
//
// To move a widget back onto the bar, drop it from here and add it to a
// Pill in RightCluster.
Item {
    readonly property bool offBar: true

    visible: false
    width: 0
    height: 0

    UnitTools {}
    EECalc {}
}
