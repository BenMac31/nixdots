pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var state: ({phase: "focus", label: "Focus", remaining: 1500, total: 1500, running: false,
        task: "", round: 0, todayCount: 0, todayMinutes: 0, history: [],
        settings: {focus: 25, short: 5, long: 15, interval: 4, autoBreak: false, autoFocus: false}})
    property bool ready: false
    property string error: ""
    readonly property string clock: Math.floor(state.remaining / 60).toString().padStart(2, "0") + ":" + (state.remaining % 60).toString().padStart(2, "0")
    readonly property string summary: state.label + " " + clock + (state.running ? "" : " · paused")
    function send(command) {
        if (ready) worker.write(JSON.stringify(command) + "\n");
    }
    function configure(key, value) {
        let settings = {};
        settings[key] = value;
        send({action: "settings", settings: settings});
    }
    property Process worker: Process {
        command: ["python3", Qt.resolvedUrl("pomodoro.py").toString().replace("file://", "")]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.state = JSON.parse(data);
                    root.ready = true;
                    root.error = root.state.error || "";
                } catch (e) { root.error = "Could not read the Pomodoro timer."; }
            }
        }
        onExited: {
            root.ready = false;
            root.error = "Pomodoro is unavailable. Retrying…";
        }
    }
    property Timer retry: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: { if (!worker.running) worker.running = true; }
    }
}
