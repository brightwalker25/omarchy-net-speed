import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Derived from Omarchy's own `omarchy.weather` bar widget
// (https://github.com/basecamp/omarchy, MIT, Copyright (c) David Heinemeier
// Hansson). The injectPanel / open / close / closeForPopoutSwitch contract
// below is what the bar requires of any widget hosting a panel, and this file
// follows that implementation closely. See LICENSE for the full notice.

// Live upload over download for the physical Wi-Fi or Ethernet link, in two
// small rows. Clicking opens the panel with the tunnel, a short graph and
// the daily totals.
//
// The bar widget owns the collector, not the panel: the rows are live, so
// `bin/net-speed` runs every intervalMs whether or not the panel is open.
// The panel reads everything it shows from this file (snapshot, the rates,
// history and formatRate) and never runs the collector itself.
BarWidget {
  id: root
  moduleName: "brightwalker25.net-speed"

  // ---- Settings

  readonly property int intervalMs: {
    var n = Number(setting("intervalMs", 1000))
    if (!isFinite(n)) n = 1000
    return Math.max(500, Math.min(5000, Math.round(n)))
  }

  readonly property string iface: {
    var s = String(setting("interface", "auto") || "").trim()
    return s === "" ? "auto" : s
  }

  readonly property string units: String(setting("units", "bits")) === "bytes" ? "bytes" : "bits"

  // ---- What the panel reads

  // The last object the collector printed, or null before the first one.
  // A failed run leaves the last good snapshot in place and sets `error`.
  property var snapshot: null

  // Bytes per second, -1 when unknown (no link, no tunnel, or a failed run).
  property real linkRx: -1
  property real linkTx: -1
  property real tunnelRx: -1
  property real tunnelTx: -1

  // One entry per sample, newest last, at most maxHistory entries:
  // {rx, tx, trx, ttx} in bytes per second (-1 when unknown) plus dt, the
  // seconds the sample covers (0 on a first sample).
  property var history: []
  readonly property int maxHistory: 120

  // Empty when the last run was fine; otherwise the collector's own error
  // or a note that it could not be run or parsed.
  property string error: ""

  // The snapshot the next rates are measured against. Cleared whenever a
  // rate across it would be meaningless.
  property var prev: null

  function formatRate(bytesPerSecond) {
    var n = Number(bytesPerSecond)
    if (!isFinite(n) || n < 0) return "--"
    var bits = root.units === "bits"
    var names = bits ? ["b/s", "Kb/s", "Mb/s", "Gb/s"] : ["B/s", "KB/s", "MB/s", "GB/s"]
    var base = bits ? 1000 : 1024
    var v = bits ? n * 8 : n
    var i = 0
    while (v >= base && i < names.length - 1) { v /= base; i++ }
    // A value that rounds up to the base reads better one unit higher:
    // "1.0 MB/s" rather than "1024 KB/s".
    if (i < names.length - 1 && Math.round(v) >= base) { v /= base; i++ }
    var digits = (i > 0 && v < 10 && v.toFixed(1) !== "10.0") ? 1 : 0
    return v.toFixed(digits) + " " + names[i]
  }

  // ---- Collector

  // The collector ships inside the plugin, so it is found relative to this
  // file rather than through PATH, as in the other brightwalker25 plugins.
  readonly property string collector: String(Qt.resolvedUrl("bin/net-speed")).replace(/^file:\/\//, "")

  readonly property var command: root.iface === "auto"
    ? [root.collector]
    : [root.collector, "--iface", root.iface]

  function poll() {
    if (proc.running) return
    proc.running = true
  }

  // Changing the pinned interface starts the readings afresh,
  // so no rate is ever measured across two different links.
  function restart() {
    root.prev = null
    root.history = []
    root.linkRx = -1
    root.linkTx = -1
    root.tunnelRx = -1
    root.tunnelTx = -1
    Qt.callLater(root.poll)
  }

  onIfaceChanged: restart()

  function fail(message) {
    root.error = message
    root.prev = null
    root.linkRx = -1
    root.linkTx = -1
    root.tunnelRx = -1
    root.tunnelTx = -1
    pushHistory(0)
  }

  // Rate of one counter between two snapshots. A counter that went
  // backwards (driver reset, interface recreated) gives 0, not a negative.
  function rate(cur, old, dt) {
    var d = Number(cur) - Number(old)
    if (!isFinite(d) || d < 0 || dt <= 0) return 0
    return d / dt
  }

  function pushHistory(dt) {
    var h = root.history.slice()
    h.push({ rx: root.linkRx, tx: root.linkTx, trx: root.tunnelRx, ttx: root.tunnelTx, dt: dt })
    while (h.length > root.maxHistory) h.shift()
    root.history = h
  }

  function ingest(text) {
    var parsed = null
    try {
      parsed = JSON.parse(String(text))
    } catch (e) {
      fail("Could not parse collector output")
      return
    }
    if (!parsed || typeof parsed !== "object") {
      fail("Collector printed no object")
      return
    }

    var old = root.prev
    // A monotonic clock that did not move forward means a zero-length
    // interval or a reboot between runs; either way there is no rate.
    var dt = (old && Number(parsed.mono) > Number(old.mono)) ? Number(parsed.mono) - Number(old.mono) : 0

    var link = parsed.link || null
    if (!link) {
      root.linkRx = -1
      root.linkTx = -1
    } else if (dt > 0 && old.link && old.link.name === link.name) {
      root.linkRx = rate(link.rx, old.link.rx, dt)
      root.linkTx = rate(link.tx, old.link.tx, dt)
    } else {
      // First sample after a start or an interface change.
      root.linkRx = 0
      root.linkTx = 0
    }

    var tun = parsed.tunnel || null
    if (!tun) {
      root.tunnelRx = -1
      root.tunnelTx = -1
    } else if (dt > 0 && old.tunnel && old.tunnel.name === tun.name) {
      root.tunnelRx = rate(tun.rx, old.tunnel.rx, dt)
      root.tunnelTx = rate(tun.tx, old.tunnel.tx, dt)
    } else {
      root.tunnelRx = 0
      root.tunnelTx = 0
    }

    root.error = parsed.error ? String(parsed.error) : ""
    root.snapshot = parsed
    root.prev = parsed
    pushHistory(dt)
  }

  Process {
    id: proc
    command: root.command
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t === "") root.fail(root.error !== "" ? root.error : "Collector printed nothing")
        else root.ingest(t)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "" && root.linkRx < 0) root.error = t
      }
    }
    // The collector always exits 0 by contract, so a non-zero exit is a
    // crash or a missing interpreter; the empty stdout above has already
    // blanked the rates.
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.error === "") root.error = "Collector exited " + exitCode
    }
  }

  Timer {
    running: true
    interval: root.intervalMs
    repeat: true
    triggeredOnStart: true
    onTriggered: root.poll()
  }

  // ---- Panel hosting

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function refresh() {
    root.poll()
  }

  // Shape contract for shell.summon/hide/toggle routing: Bar.findPanelWidget
  // needs open/close/opened on the bar-widget root, not on the nested panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // The bar prefers closeForPopoutSwitch over close when handing one panel
  // over to another, and reads popoutSwitchClosing back off the owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // The open-panel dot takes the width of the painted rows, as the clock's
  // takes the width of its label.
  readonly property real openPanelIndicatorWidth: vertical ? 0 : rows.width

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // ---- Bar look

  // Two rows share the bar height, with a little padding above and below,
  // in a font no larger than the caption size. The same arithmetic as
  // NetworkStats, whose idea this is.
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real rowPadding: Math.max(0, Math.min(Style.space(2), (barSize - 14) / 2))
  readonly property real rowHeight: (barSize - rowPadding * 2) / 2
  readonly property real rowFontSize: Math.max(7, Math.min(Style.font.caption, Math.floor(rowHeight - 1)))

  // Upload blue, download green, fixed so they read the same on every
  // theme. Blue carries no meaning in the other brightwalker25 widgets,
  // where red and amber mean a problem; the green is the one they use.
  readonly property color upColor: "#58a6ff"
  readonly property color downColor: "#3fb950"

  readonly property string upText: root.formatRate(root.linkTx)
  readonly property string downText: root.formatRate(root.linkRx)

  // The widest value each unit system can print, measured once in the bar
  // font, so the widget keeps one width whatever the rate is.
  TextMetrics {
    id: arrowProbe
    font.family: root.fontFamily
    font.pixelSize: root.rowFontSize
    text: "↑"
  }

  TextMetrics {
    id: valueProbe
    font.family: root.fontFamily
    font.pixelSize: root.rowFontSize
    text: root.units === "bits" ? "888 Kb/s" : "8888 KB/s"
  }

  readonly property real arrowWidth: Math.ceil(arrowProbe.advanceWidth)
  readonly property real valueWidth: Math.ceil(valueProbe.advanceWidth)
  readonly property real columnGap: Style.space(3)

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 5
    fixedWidth: root.vertical ? -1 : Math.ceil(rows.width + scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    // Suppressed because the panel is the detail view.
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Column {
      id: rows
      visible: !root.vertical
      anchors.centerIn: parent
      width: root.arrowWidth + root.columnGap + root.valueWidth
      spacing: 0

      Repeater {
        model: [
          { arrow: "↑", value: root.upText, tint: root.upColor },
          { arrow: "↓", value: root.downText, tint: root.downColor }
        ]

        Item {
          id: row
          required property var modelData
          width: rows.width
          height: root.rowHeight

          Text {
            width: root.arrowWidth
            height: parent.height
            text: row.modelData.arrow
            textFormat: Text.PlainText
            color: row.modelData.tint
            font.family: root.fontFamily
            font.pixelSize: root.rowFontSize
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }

          Text {
            x: root.arrowWidth + root.columnGap
            width: root.valueWidth
            height: parent.height
            text: row.modelData.value
            textFormat: Text.PlainText
            color: row.modelData.tint
            font.family: root.fontFamily
            font.pixelSize: root.rowFontSize
            font.features: { "tnum": 1 }
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }

    // A vertical bar has no room for two rates side by side, so it gets a
    // single glyph (nf-md-swap-vertical) that still opens the panel.
    OpticalGlyph {
      visible: root.vertical
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      text: "󰓡"
      fontFamily: button.fontFamily
      fontSize: Style.bar.iconFont
      color: button.foreground
    }
  }
}
