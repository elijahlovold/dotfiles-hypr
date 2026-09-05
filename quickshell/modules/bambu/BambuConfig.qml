pragma Singleton
import QtQuick
import Quickshell

// Only the socket path - the printer IP/serial/access code stay out of QML
// entirely and live in bambu-statusd.env (see bambu-statusd.env.example),
// read only by bambu_statusd.py. Must match $BAMBU_SOCKET_PATH if that's
// overridden in the env file, or the default it computes from
// $XDG_RUNTIME_DIR otherwise.
Singleton {
    readonly property string socketPath: "/run/user/1000/bambu-status.sock"
}
