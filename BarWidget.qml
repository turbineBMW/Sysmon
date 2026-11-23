import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One system-monitor stat: a glyph with a live meter beside it on the bar, and
// an Omarchy card with the detail behind it.
//
// Ported from willshell's SystemMonitor bar widget. The pill keeps willshell's
// vertical meter next to the icon; everything else — the card, the hero, the
// rotating status phrase — follows omarchy.power's battery panel.
Panel {
  id: root
  moduleName: "turbinebmw.sysmon"
  ipcTarget: ""

  // ---- config --------------------------------------------------------------

  readonly property string stat: String(setting("stat", "cpu"))
  readonly property string mount: String(setting("mount", "/"))
  readonly property int fanMaxRpm: Math.max(1, Number(setting("fanMaxRpm", 8800)))
  readonly property int warningThreshold: Number(setting("warningThreshold", 75))
  readonly property int criticalThreshold: Number(setting("criticalThreshold", 90))

  readonly property var def: Model.statDef(stat)

  // ---- theme ---------------------------------------------------------------

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // ---- service -------------------------------------------------------------

  // The sampler is this plugin's own service kind, mounted once for every pill
  // on the bar. It may not exist yet on the first frame after a rescan, so the
  // lookup retries until it lands.
  property var service: null

  function resolveService() {
    var sh = bar ? bar.shell : null
    var found = (sh && typeof sh.serviceFor === "function") ? sh.serviceFor("turbinebmw.sysmon") : null
    if (found !== service) service = found
  }

  onBarChanged: resolveService()
  Component.onCompleted: resolveService()

  // The service owns the single IPC target and relays by stat name, so
  // `omarchy-shell sysmon toggle memory` reaches exactly one card.
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPanelRequest(stat, action) {
      if (stat !== "" && stat !== root.stat) return
      if (action === "open") root.open()
      else if (action === "close") root.close()
      else root.toggle()
    }
  }

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onShellChanged() { root.resolveService() }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.service === null
    onTriggered: root.resolveService()
  }

  // ---- readings ------------------------------------------------------------

  readonly property var diskEntry: service ? Model.diskEntryFor(service, mount) : null

  // Raw reading in the stat's own unit, or -1 when unavailable.
  readonly property real rawValue: {
    if (!service) return -1
    switch (stat) {
    case "gpu": return service.gpuPercent
    case "temperature": return service.tempC
    case "memory": return service.memPercent
    case "fan": return service.fanRpm
    case "disk": return diskEntry ? diskEntry.percent : -1
    default: return service.cpuPercent
    }
  }

  readonly property bool hasValue: rawValue >= 0

  // Full scale for the meter. Percentages are their own scale; a temperature
  // reads against 100 °C and a fan against its configured ceiling.
  readonly property real fullScale: {
    if (stat === "temperature") return 100
    if (stat === "fan") return fanMaxRpm
    return 100
  }

  readonly property real ratio: hasValue ? Model.clamp(rawValue / fullScale, 0, 1) : 0

  // Thresholds in the same 0..1 space the meter draws, so the phrase tier, the
  // meter color, and the alarm state can never disagree.
  readonly property real warnRatio: {
    if (stat === "temperature") return 0.70
    if (stat === "fan") return 0.60
    return Model.clamp(warningThreshold / 100, 0, 1)
  }
  readonly property real critRatio: {
    if (stat === "temperature") return 0.85
    if (stat === "fan") return 0.85
    return Model.clamp(criticalThreshold / 100, 0, 1)
  }

  readonly property bool alarming: hasValue && ratio >= critRatio
  readonly property color meterColor: alarming ? urgent : foreground

  readonly property string heroValue: {
    if (!hasValue) return "—"
    if (stat === "fan") return String(rawValue)
    return rawValue + def.unit
  }
  // The fan's unit is long enough to want its own line under the number.
  readonly property string heroValueSuffix: stat === "fan" ? "RPM" : ""

  readonly property string tooltipText: def.title + " · " + (service ? Model.shortValue(stat, service, mount) : "—")

  // ---- rotating status phrase ---------------------------------------------

  property int phraseIndex: 0

  readonly property string statusText: hasValue
    ? Model.phraseFor(stat, ratio, warnRatio, critRatio, phraseIndex)
    : "No reading"

  // Rotate only while the card is open — nobody is reading the phrase
  // otherwise, and the fade would be animating a hidden item.
  Timer {
    interval: 2800
    running: root.opened && root.hasValue
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = Model.phraseCount(root.stat, root.ratio, root.warnRatio, root.critRatio)
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // ---- geometry ------------------------------------------------------------

  readonly property bool vertical: bar ? bar.vertical : false
  // Painted height of the icon art. The bar's other widgets paint their
  // glyphs about 11px tall at the default bar size; the icons are scaled to
  // land on the same number so this group does not read as a size step.
  readonly property int iconInk: Math.max(6, Math.round(Style.bar.iconCanvas * 0.7))
  readonly property int heroIconInk: Math.round(Style.font.display * 0.9)
  readonly property int meterThickness: Math.max(3, Style.space(4))
  // Long axis of the pill meter. Matched to the glyph's ink rather than run
  // over the whole icon canvas, so a meter is optically the same height as
  // the icon it belongs to instead of overshooting it top and bottom.
  readonly property int meterLength: root.iconInk
  readonly property int meterGap: Style.space(1)
  // Glyph and meter are one object, so they sit a hair apart and the padding
  // goes on the outside. Giving the glyph a full icon slot instead would put
  // more space between a pill's glyph and its own meter than between that
  // meter and the next pill, and the meters would read as belonging to the
  // icon on their right.
  readonly property int pillPadding: Style.space(6)
  readonly property int contentLength: Style.bar.iconCanvas + meterGap + meterThickness
  readonly property int slotLength: contentLength + pillPadding * 2

  implicitWidth: vertical ? (bar ? bar.barSize : Style.bar.sizeVertical) : slotLength
  implicitHeight: vertical ? slotLength : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  onOpenedChanged: {
    if (!service) return
    if (opened) service.addViewer()
    else service.removeViewer()
  }

  Component.onDestruction: if (service && opened) service.removeViewer()

  // ---- pill menu -----------------------------------------------------------

  // Right click opens a checklist of which stats have a pill on the bar. A
  // widget cannot rewrite the bar layout itself, so ticking a stat runs
  // scripts/sysmon-pills, which edits shell.json the way `omarchy bar` does;
  // the bar then builds or drops that pill.
  property bool menuOpen: false

  readonly property string pillsScript: String(Qt.resolvedUrl("scripts/sysmon-pills")).replace(/^file:\/\//, "")

  // Stats with a pill anywhere on the bar, read from the layout the bar hands
  // its widgets, so every pill's menu agrees with the bar as it stands.
  readonly property var statsOnBar: {
    var layout = bar && bar.layoutConfig ? bar.layoutConfig : ({})
    var found = []
    for (var section in layout) {
      var entries = Array.isArray(layout[section]) ? layout[section] : []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!entry || entry.id !== root.moduleName) continue
        var s = String(entry.stat || "cpu")
        if (found.indexOf(s) === -1) found.push(s)
      }
    }
    return found
  }

  // The stat whose change is still on its way to the bar. Further clicks wait
  // for it, so one menu never queues edits against a layout it has not seen.
  property string pendingStat: ""

  function statOnBar(s) { return statsOnBar.indexOf(s) !== -1 }
  // The last pill stays: it is the only way back into this menu.
  function statLocked(s) { return statOnBar(s) && statsOnBar.length <= 1 }

  function togglePill(s) {
    if (pendingStat !== "" || statLocked(s)) return
    pendingStat = s
    Quickshell.execDetached([pillsScript, s, statOnBar(s) ? "off" : "on"])
  }

  onStatsOnBarChanged: pendingStat = ""

  Timer {
    interval: 4000
    running: root.pendingStat !== ""
    onTriggered: root.pendingStat = ""
  }

  // PopupCard closes through its owner; this one closes the menu, not the
  // card, and the bar's popout handoff closes it when the card opens.
  QtObject {
    id: menuOwner
    function close() { root.menuOpen = false }
  }

  // ---- bar pill ------------------------------------------------------------

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tooltipText
    fixedWidth: root.vertical ? -1 : root.slotLength
    fixedHeight: root.vertical ? root.slotLength : -1
    active: root.alarming

    onPressed: function(code) {
      if (code === Qt.RightButton) root.menuOpen = !root.menuOpen
      else root.toggle()
    }

    // Icon and meter share one box: side by side on a horizontal bar, stacked
    // on a vertical one, so the meter always runs along the bar's long axis.
    Item {
      anchors.centerIn: parent
      width: root.vertical ? Style.bar.iconCanvas : root.contentLength
      height: root.vertical ? root.contentLength : Style.bar.iconCanvas

      StatIcon {
        id: pillGlyph
        width: root.vertical ? parent.width : Style.bar.iconCanvas
        height: root.vertical ? Style.bar.iconCanvas : parent.height
        anchors.left: parent.left
        anchors.top: parent.top
        stat: root.stat
        inkHeight: root.iconInk
        color: root.alarming ? root.urgent : (root.bar ? root.bar.barForeground : Color.foreground)

        Behavior on color { ColorAnimation { duration: 160 } }
      }

      // willshell's vertical meter, kept: a rounded track as long as the glyph
      // is tall, filling from the bottom up. On a vertical bar it lies flat
      // under the glyph and fills left to right instead.
      //
      // Both the track and its fill are placed with explicit x/y rather than
      // anchors. An anchor bound to `vertical ? undefined : parent.bottom`
      // sets itself on the first evaluation (before the bar is injected and
      // `vertical` can be true) and then refuses to clear, which left the fill
      // dangling below its own track on a left-hand bar.
      Item {
        id: pillMeter
        width: root.vertical ? root.meterLength : root.meterThickness
        height: root.vertical ? root.meterThickness : root.meterLength
        x: root.vertical ? Math.round((parent.width - width) / 2) : parent.width - width
        y: root.vertical ? parent.height - height : Math.round((parent.height - height) / 2)

        Rectangle {
          anchors.fill: parent
          radius: Math.min(width, height) / 2
          color: root.track
        }

        Rectangle {
          visible: root.hasValue && root.ratio > 0
          radius: Math.min(width, height) / 2
          color: root.meterColor
          width: root.vertical ? Math.max(parent.height, parent.width * root.ratio) : parent.width
          height: root.vertical ? parent.height : Math.max(parent.width, parent.height * root.ratio)
          x: 0
          y: root.vertical ? 0 : parent.height - height

          Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }
    }
  }

  // ---- menu ----------------------------------------------------------------

  PopupCard {
    id: menu
    anchorItem: button
    owner: menuOwner
    bar: root.bar
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(260))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        text: "Show on bar"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: Model.statIds()

        Toggle {
          required property string modelData
          width: menuColumn.width
          label: Model.statDef(modelData).title
          description: root.statLocked(modelData) ? "The last pill stays on the bar" : ""
          checked: root.pendingStat === modelData ? !root.statOnBar(modelData) : root.statOnBar(modelData)
          opacity: root.statLocked(modelData) ? 0.6 : 1
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.togglePill(modelData)
        }
      }

      PanelSeparator { foreground: root.foreground }

      Button {
        width: parent.width
        text: "Open btop"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          root.menuOpen = false
          if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
        }
      }
    }
  }

  // ---- card ----------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          cardFlick.contentY = Model.clamp(cardFlick.contentY + dy * Style.space(48), 0,
                                           Math.max(0, cardFlick.contentHeight - cardFlick.height))
      }

      Flickable {
        id: cardFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: cardFlick.width
          spacing: Style.space(14)

          // ---------- Hero: glyph · title/status · value ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValueColumn.implicitHeight)

            StatIcon {
              id: heroIcon
              stat: root.stat
              inkHeight: root.heroIconInk
              color: root.alarming ? root.urgent : root.foreground
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Behavior on color { ColorAnimation { duration: 200 } }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroValueColumn.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: root.def.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroStatus
                textFormat: Text.PlainText
                text: root.statusText.toUpperCase()
                color: root.alarming ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Column {
              id: heroValueColumn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                textFormat: Text.PlainText
                text: root.heroValue
                color: root.alarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
                horizontalAlignment: Text.AlignRight
                anchors.right: parent.right

                Behavior on color { ColorAnimation { duration: 200 } }
              }

              Text {
                textFormat: Text.PlainText
                visible: root.heroValueSuffix !== ""
                text: root.heroValueSuffix
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                horizontalAlignment: Text.AlignRight
                anchors.right: parent.right
              }
            }
          }

          // ---------- Headline meter ----------
          Item {
            width: parent.width
            implicitHeight: Style.space(8)

            Rectangle {
              id: heroTrack
              anchors.fill: parent
              radius: height / 2
              color: root.track
            }

            Rectangle {
              anchors.left: heroTrack.left
              anchors.verticalCenter: heroTrack.verticalCenter
              height: heroTrack.height
              radius: heroTrack.radius
              color: root.meterColor
              width: Math.max(heroTrack.height, heroTrack.width * root.ratio)

              Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 220 } }
            }
          }

          // ---------- CPU ----------
          Row {
            visible: root.stat === "cpu"
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Frequency"; value: root.service ? Model.formatMhz(root.service.cpuFrequencyMhz) : "—" }
              InfoPair { label: "Cores"; value: root.service && root.service.cpuCores.length > 0 ? String(root.service.cpuCores.length) : "—" }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair {
                label: "Load 1m"
                value: root.service && root.service.loadOne >= 0 ? root.service.loadOne.toFixed(2) : "—"
              }
              // Two numbers share one row here; spelling out both labels would
              // push the value off the edge of the column.
              InfoPair {
                label: "5m / 15m"
                value: root.service && root.service.loadFive >= 0
                  ? root.service.loadFive.toFixed(2) + " / " + root.service.loadFifteen.toFixed(2)
                  : "—"
              }
            }
          }

          PanelSeparator { visible: root.stat === "cpu"; foreground: root.foreground }

          Column {
            visible: root.stat === "cpu"
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "PER-CORE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Grid {
              id: coreGrid
              width: parent.width
              columns: root.service && root.service.cpuCores.length > 8 ? 2 : 1
              rowSpacing: Style.space(4)
              columnSpacing: Style.space(14)

              readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

              Repeater {
                model: root.service ? root.service.cpuCores : []

                Row {
                  required property int index
                  required property var modelData
                  width: coreGrid.cellWidth
                  spacing: Style.space(8)

                  Text {
                    text: index
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    width: Style.space(18)
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  MiniMeter {
                    width: parent.width - Style.space(18) - Style.space(34) - parent.spacing * 2
                    value: Model.clamp(modelData / 100, 0, 1)
                    hot: modelData >= root.criticalThreshold
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: modelData >= 0 ? modelData + "%" : "—"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    width: Style.space(34)
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }

          // ---------- GPU ----------
          Row {
            visible: root.stat === "gpu"
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Clock"; value: root.service ? Model.formatMhz(root.service.gpuClockMhz) : "—" }
              InfoPair {
                label: "Temp"
                value: root.service && root.service.gpuTempC >= 0 ? root.service.gpuTempC + "°C" : "—"
              }
              InfoPair {
                label: "Video"
                value: root.service && root.service.gpuVideoPercent >= 0 ? root.service.gpuVideoPercent + "%" : "—"
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              // On an APU the only power sensor is PPT, the whole package, so
              // say that rather than passing it off as the GPU's own draw.
              InfoPair {
                label: root.service && root.service.gpuPowerLabel === "PPT" ? "Package" : "Power"
                value: root.service ? Model.formatWatts(root.service.gpuPowerW) : "—"
              }
              InfoPair { label: "Device"; value: root.service && root.service.gpuCard !== "" ? root.service.gpuCard : "—" }
              InfoPair { label: "Driver"; value: root.service && root.service.gpuDriver !== "" ? root.service.gpuDriver : "—" }
            }
          }

          Column {
            visible: root.stat === "gpu" && !!root.service && root.service.gpuDevice !== ""
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "GPU MEMORY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // VRAM is the dedicated carve-out; GTT is system RAM the GPU has
            // mapped. On an APU most of the model weights live in GTT.
            Repeater {
              model: root.service ? [
                { "label": "VRAM", "used": root.service.gpuVramUsed, "total": root.service.gpuVramTotal },
                { "label": "Shared", "used": root.service.gpuGttUsed, "total": root.service.gpuGttTotal }
              ] : []

              Row {
                required property var modelData
                visible: modelData.total > 0
                width: parent.width
                spacing: Style.space(10)

                Text {
                  id: gpuMemLabel
                  text: modelData.label
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(56)
                  anchors.verticalCenter: parent.verticalCenter
                }

                MiniMeter {
                  width: parent.width - gpuMemLabel.width - gpuMemValue.width - parent.spacing * 2
                  value: modelData.total > 0 ? Model.clamp(modelData.used / modelData.total, 0, 1) : 0
                  hot: modelData.total > 0 && modelData.used / modelData.total >= root.critRatio
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: gpuMemValue
                  text: Model.formatBytes(modelData.used) + " / " + Model.formatBytes(modelData.total)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(130)
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          Text {
            visible: root.stat === "gpu" && (!root.service || root.service.gpuDevice === "")
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No GPU busy reading found. Sysmon reads amdgpu's gpu_busy_percent; Intel and NVIDIA drivers don't expose one."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---------- Temperature ----------
          Row {
            visible: root.stat === "temperature"
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Sensor"; value: root.service ? Model.sensorLabel(root.service.tempPath) : "—" }
              InfoPair {
                label: "Fan"
                value: root.service && root.service.fanRpm >= 0 ? Model.formatRpm(root.service.fanRpm) : "—"
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Warns at"; value: Math.round(root.warnRatio * root.fullScale) + "°C" }
              InfoPair { label: "Critical at"; value: Math.round(root.critRatio * root.fullScale) + "°C" }
            }
          }

          // ---------- Memory ----------
          Row {
            visible: root.stat === "memory"
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Used"; value: root.service ? Model.formatKb(root.service.memUsedKb) : "—" }
              InfoPair { label: "Available"; value: root.service ? Model.formatKb(root.service.memAvailableKb) : "—" }
              InfoPair { label: "Free"; value: root.service ? Model.formatKb(root.service.memFreeKb) : "—" }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Cached"; value: root.service ? Model.formatKb(root.service.memCachedKb) : "—" }
              InfoPair { label: "Buffers"; value: root.service ? Model.formatKb(root.service.memBuffersKb) : "—" }
              InfoPair { label: "Total"; value: root.service ? Model.formatKb(root.service.memTotalKb) : "—" }
            }
          }

          Column {
            visible: root.stat === "memory" && !!root.service && root.service.swapTotalKb > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "SWAP"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              MiniMeter {
                width: parent.width - swapValue.width - parent.spacing
                value: root.service && root.service.swapTotalKb > 0
                  ? Model.clamp(root.service.swapUsedKb / root.service.swapTotalKb, 0, 1) : 0
                hot: !!root.service && root.service.swapTotalKb > 0
                  && root.service.swapUsedKb / root.service.swapTotalKb >= root.critRatio
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: swapValue
                text: root.service
                  ? Model.formatKb(root.service.swapUsedKb) + " / " + Model.formatKb(root.service.swapTotalKb)
                  : "—"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: Style.space(140)
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          // ---------- Fan ----------
          Column {
            visible: root.stat === "fan"
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "FANS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.service ? root.service.fans : []

              Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(10)

                Text {
                  id: fanLabel
                  text: modelData.label
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: Style.space(110)
                  anchors.verticalCenter: parent.verticalCenter
                }

                MiniMeter {
                  width: parent.width - fanLabel.width - fanValue.width - parent.spacing * 2
                  value: Model.clamp(modelData.rpm / root.fanMaxRpm, 0, 1)
                  hot: modelData.rpm / root.fanMaxRpm >= root.critRatio
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: fanValue
                  text: Model.formatRpm(modelData.rpm)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(58)
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Text {
              visible: !root.service || root.service.fans.length === 0
              text: "No fan sensors found"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ---------- Disk ----------
          Column {
            visible: root.stat === "disk"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "FILESYSTEMS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.service ? root.service.disks : []

              Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(fsMount.implicitHeight, fsSize.implicitHeight)

                  Text {
                    id: fsMount
                    text: modelData.mount
                    color: modelData.mount === root.mount ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: modelData.mount === root.mount
                    elide: Text.ElideRight
                    anchors.left: parent.left
                    anchors.right: fsSize.left
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: fsSize
                    text: Model.formatKb(modelData.usedKb) + " / " + Model.formatKb(modelData.totalKb)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MiniMeter {
                  width: parent.width
                  value: Model.clamp(modelData.percent / 100, 0, 1)
                  hot: modelData.percent >= root.criticalThreshold
                }
              }
            }

            Text {
              visible: !root.service || root.service.disks.length === 0
              text: "No filesystems reported yet"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }

  // ---- shared card pieces --------------------------------------------------

  component MiniMeter: Item {
    id: mini
    property real value: 0
    property bool hot: false

    implicitHeight: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
    height: implicitHeight

    Rectangle {
      id: miniTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: miniTrack.left
      anchors.verticalCenter: miniTrack.verticalCenter
      height: miniTrack.height
      radius: miniTrack.radius
      width: miniTrack.width * Model.clamp(mini.value, 0, 1)
      color: mini.hot ? root.urgent : root.foreground

      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Text {
      id: pairLabel
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: Math.max(0, parent.width - pairLabel.implicitWidth - pairValue.implicitWidth - parent.spacing * 2)
      height: 1
    }

    Text {
      id: pairValue
      textFormat: Text.PlainText
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
