import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: chart
    property var points: []
    property int selectedIndex: -1
    readonly property var selected: points.length ? points[Math.min(points.length - 1, selectedIndex < 0 ? points.length - 1 : selectedIndex)] : null
    readonly property real firstDay: points.length ? Date.parse(points[0].day + "T00:00:00Z") : 0
    readonly property real lastDay: points.length ? Date.parse(points[points.length - 1].day + "T00:00:00Z") : 0
    readonly property int ceiling: Math.max(1, ...points.map(p => Math.max(p.users || 0, p.dau || 0)))
    spacing: 5

    RowLayout {
        spacing: 12
        Label { text: "━ Users"; color: Theme.bright; font.pixelSize: 11 }
        Label { text: "┄ DAU"; color: Theme.warning; font.pixelSize: 11 }
    }
    Label {
        Layout.fillWidth: true
        text: chart.selected ? chart.selected.day + " UTC" : "Waiting for daily activity"
        color: Theme.muted
        font.pixelSize: 10
    }
    Label {
        Layout.fillWidth: true
        text: chart.selected ? "Users " + (chart.selected.users === null ? "—" : chart.selected.users) + " · DAU " + chart.selected.dau : ""
        color: Theme.text
        font.pixelSize: 11
    }
    Canvas {
        id: plot
        Layout.fillWidth: true
        implicitHeight: 110
        readonly property real plotLeft: 28
        readonly property real plotRight: Math.max(plotLeft + 1, width - 5)
        readonly property real plotTop: 8
        readonly property real plotBottom: height - 8
        function pointX(point) {
            return chart.lastDay === chart.firstDay ? (plotLeft + plotRight) / 2 : plotLeft + (Date.parse(point.day + "T00:00:00Z") - chart.firstDay) / (chart.lastDay - chart.firstDay) * (plotRight - plotLeft);
        }
        function pointY(value) { return plotBottom - value / chart.ceiling * (plotBottom - plotTop); }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: chart
            function onPointsChanged() { plot.requestPaint(); }
            function onSelectedIndexChanged() { plot.requestPaint(); }
        }
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.font = "10px sans-serif";
            c.fillStyle = Theme.muted;
            c.textAlign = "right";
            c.fillText(String(chart.ceiling), plotLeft - 5, plotTop + 4);
            c.fillText("0", plotLeft - 5, plotBottom + 3);
            c.strokeStyle = Theme.rule;
            c.beginPath();
            c.moveTo(plotLeft, plotTop); c.lineTo(plotRight, plotTop);
            c.moveTo(plotLeft, plotBottom); c.lineTo(plotRight, plotBottom);
            c.stroke();
            if (!chart.points.length) return;
            function series(field, color, dashed) {
                c.strokeStyle = color; c.fillStyle = color; c.lineWidth = 2;
                c.setLineDash(dashed ? [4, 3] : []);
                c.beginPath();
                let previous = null;
                for (const point of chart.points) {
                    const value = point[field];
                    if (value === null || value === undefined) { previous = null; continue; }
                    // A missing date is a gap, not a zero or an interpolated day.
                    if (previous && Date.parse(point.day) - Date.parse(previous.day) === 86400000)
                        c.lineTo(pointX(point), pointY(value));
                    else c.moveTo(pointX(point), pointY(value));
                    previous = point;
                }
                c.stroke(); c.setLineDash([]);
                for (const point of chart.points) {
                    if (point[field] === null || point[field] === undefined) continue;
                    c.beginPath(); c.arc(pointX(point), pointY(point[field]), point === chart.selected ? 3 : 1.7, 0, Math.PI * 2); c.fill();
                }
            }
            series("users", Theme.bright, false);
            series("dau", Theme.warning, true);
            if (chart.selectedIndex >= 0) {
                c.strokeStyle = Theme.muted; c.lineWidth = 1; c.setLineDash([2, 3]);
                c.beginPath(); c.moveTo(pointX(chart.selected), plotTop); c.lineTo(pointX(chart.selected), plotBottom); c.stroke();
            }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: mouse => {
                let nearest = -1, distance = Infinity;
                chart.points.forEach((point, i) => {
                    const d = Math.abs(plot.pointX(point) - mouse.x);
                    if (d < distance) { nearest = i; distance = d; }
                });
                chart.selectedIndex = nearest;
            }
            onExited: chart.selectedIndex = -1
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Label { text: chart.points.length ? chart.points[0].day.slice(5) : ""; color: Theme.muted; font.pixelSize: 10 }
        Item { Layout.fillWidth: true }
        Label { text: chart.points.length ? chart.points[chart.points.length - 1].day.slice(5) : ""; color: Theme.muted; font.pixelSize: 10 }
    }
}
