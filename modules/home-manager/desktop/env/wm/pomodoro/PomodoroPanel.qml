import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

ColumnLayout {
    id: panel
    anchors.margins: 16
    spacing: 12
    readonly property var timer: PomodoroState.state
    function takeFocus() { focusLabel.text = timer.task; focusLabel.forceActiveFocus(); }
    Keys.onEscapePressed: Desktop.closeLauncher()
    Shortcut {
        sequence: "Ctrl+Return"
        context: Qt.WindowShortcut
        enabled: panel.visible && PomodoroState.ready
        onActivated: {
            PomodoroState.send({action: "task", task: focusLabel.text});
            PomodoroState.send({action: "toggle"});
        }
    }

    component Duration: RowLayout {
        property string title
        property string setting
        property int maximum: 180
        spacing: 6
        Label { text: title; color: Theme.muted; font.pixelSize: 11 }
        Action {
            text: "−"
            enabled: PomodoroState.ready && !panel.timer.running && panel.timer.settings[setting] > 1
            onClicked: PomodoroState.configure(setting, panel.timer.settings[setting] - 1)
        }
        Label {
            text: panel.timer.settings[setting]
            horizontalAlignment: Text.AlignHCenter
            Layout.minimumWidth: 22
            font.pixelSize: 12
        }
        Action {
            text: "+"
            enabled: PomodoroState.ready && !panel.timer.running && panel.timer.settings[setting] < maximum
            onClicked: PomodoroState.configure(setting, panel.timer.settings[setting] + 1)
        }
    }

    Masthead {}
    Controls.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: parent.width
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [{phase: "focus", name: "Focus"}, {phase: "short", name: "Short break"}, {phase: "long", name: "Long break"}]
                    Choice {
                        required property var modelData
                        text: modelData.name
                        active: panel.timer.phase === modelData.phase
                        enabled: PomodoroState.ready && !panel.timer.running
                        onClicked: PomodoroState.send({action: "phase", phase: modelData.phase})
                    }
                }
                Item { Layout.fillWidth: true }
                Caption { text: panel.timer.running ? "Running" : "Paused"; size: 12 }
            }
            Figure {
                text: PomodoroState.clock
                size: 72
                font.family: Theme.mono
                Layout.alignment: Qt.AlignHCenter
                Accessible.name: panel.timer.label + ", " + text
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                color: Theme.rule
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, 1 - panel.timer.remaining / panel.timer.total))
                    height: parent.height
                    color: panel.timer.phase === "focus" ? Theme.accent : Theme.good
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                Action {
                    text: panel.timer.running ? "Pause" : "Start " + panel.timer.label.toLowerCase()
                    active: true
                    enabled: PomodoroState.ready
                    onClicked: PomodoroState.send({action: "toggle"})
                }
                Action { text: "Reset"; enabled: PomodoroState.ready; onClicked: PomodoroState.send({action: "reset"}) }
                Action { text: "Skip"; enabled: PomodoroState.ready; onClicked: PomodoroState.send({action: "skip"}) }
            }
            Controls.TextField {
                id: focusLabel
                Layout.fillWidth: true
                implicitHeight: 40
                maximumLength: 200
                placeholderText: "What are you focusing on?"
                Component.onCompleted: text = panel.timer.task
                color: Theme.text
                placeholderTextColor: Theme.muted
                font { family: Theme.sans; pixelSize: 14 }
                padding: 10
                background: Rectangle { color: Theme.sunken; border.color: focusLabel.activeFocus ? Theme.accent : Theme.rule }
                enabled: PomodoroState.ready
                onEditingFinished: { if (text !== panel.timer.task) PomodoroState.send({action: "task", task: text}); }
                onAccepted: {
                    PomodoroState.send({action: "task", task: text});
                    if (!panel.timer.running) PomodoroState.send({action: "toggle"});
                }
                Keys.onEscapePressed: Desktop.closeLauncher()
            }
            RowLayout {
                Layout.fillWidth: true
                Figure { text: panel.timer.todayCount + " completed today"; size: 18 }
                Item { Layout.fillWidth: true }
                Caption { text: panel.timer.todayMinutes + " min focused · " + (panel.timer.settings.interval - panel.timer.round % panel.timer.settings.interval) + " until long break"; size: 12 }
            }
            Rule {}
            Heading { text: "Session settings" }
            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 16
                Duration { title: "Focus"; setting: "focus" }
                Duration { title: "Short break"; setting: "short" }
                Duration { title: "Long break"; setting: "long" }
                Duration { title: "Every"; setting: "interval"; maximum: 12 }
            }
            RowLayout {
                spacing: 12
                Choice { text: "Auto-start breaks"; active: panel.timer.settings.autoBreak; enabled: PomodoroState.ready && !panel.timer.running; onClicked: PomodoroState.configure("autoBreak", !panel.timer.settings.autoBreak) }
                Choice { text: "Auto-start focus"; active: panel.timer.settings.autoFocus; enabled: PomodoroState.ready && !panel.timer.running; onClicked: PomodoroState.configure("autoFocus", !panel.timer.settings.autoFocus) }
            }
            Caption {
                Layout.fillWidth: true
                size: 11
                text: panel.timer.running ? "Pause to adjust settings or choose another phase." : "Durations are in minutes. Changing settings resets this phase. Skipped focus sessions are not counted."
            }
            Rule {}
            Heading { text: "Recent focus sessions" }
            Caption { visible: panel.timer.history.length === 0; text: "Your completed sessions will appear here."; size: 12 }
            Repeater {
                model: panel.timer.history
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Label { text: modelData.task || "Focus"; Layout.fillWidth: true; font.pixelSize: 12 }
                    Caption { text: modelData.minutes + " min · " + new Date(modelData.ended * 1000).toLocaleString(Qt.locale(), "MMM d, hh:mm"); size: 11 }
                }
            }
        }
    }
    Caption { visible: PomodoroState.error !== ""; text: PomodoroState.error; color: Theme.warning; Layout.fillWidth: true }
    Rule {}
    RowLayout {
        KeyHint { keys: ["Ctrl", "↵"]; text: "start or pause" }
        KeyHint { keys: ["Shift", "Tab"]; text: "next place" }
        Item { Layout.fillWidth: true }
        KeyHint { keys: ["Esc"]; text: "close" }
    }
}
