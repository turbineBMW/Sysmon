import QtQuick
import Quickshell
import Quickshell.Io

// One sampler for every system-monitor pill on the bar. Each bar widget is an
// independent instance, but they all read these properties, so /proc is walked
// once per tick no matter how many pills are showing.
//
// The fast path spawns no processes: /proc and /sys are read in-process via
// FileView on one repeating timer. A slow shell poll covers what genuinely
// needs a process (df) and doubles as discovery of which sysfs files the
// sampler should read — the thermal sensor, every hwmon fan, and the GPU — so hardware
// that appears late still gets found.
//
// Ported from willshell's SystemStatsService.
Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null

  // ---- published readings --------------------------------------------------

  property int cpuPercent: -1
  property var cpuCores: []
  property real cpuFrequencyMhz: -1
  property real loadOne: -1
  property real loadFive: -1
  property real loadFifteen: -1

  property int memPercent: -1
  property int memTotalKb: -1
  property int memUsedKb: -1
  property int memFreeKb: -1
  property int memAvailableKb: -1
  property int memCachedKb: -1
  property int memBuffersKb: -1
  property int swapTotalKb: -1
  property int swapUsedKb: -1

  property int tempC: -1
  property string tempPath: ""

  // fanRpm is the first spinning fan — the one the bar pill shows. `fans`
  // carries every discovered fan as {label, rpm} for the card.
  property int fanRpm: -1
  property var fans: []

  // One {percent, usedKb, freeKb, totalKb, device, mount} per real filesystem.
  property var disks: []

  // The first GPU whose driver reports a busy percentage (amdgpu does). Memory
  // sizes are bytes and can pass 2^31, so they are reals, not ints.
  property int gpuPercent: -1
  property int gpuVideoPercent: -1
  property real gpuVramUsed: -1
  property real gpuVramTotal: -1
  property real gpuGttUsed: -1
  property real gpuGttTotal: -1
  property int gpuTempC: -1
  property real gpuPowerW: -1
  property real gpuClockMhz: -1

  // Rolling last-60-samples history, always accumulated so a card's graph is
  // pre-warmed the moment it opens.
  property var cpuHistory: []
  property var memHistory: []
  property var gpuHistory: []

  // ---- viewer-driven cadence ----------------------------------------------

  // Cards call addViewer()/removeViewer() while open. df is the only cost here
  // and it is cheap, but 30s is plenty when nobody is looking at it.
  property int viewers: 0

  function addViewer() { viewers = viewers + 1 }
  function removeViewer() { viewers = Math.max(0, viewers - 1) }

  onViewersChanged: if (viewers > 0) slowPoll.restart()

  // ---- card IPC ------------------------------------------------------------

  // Every pill is a separate widget instance, so they cannot each own an IPC
  // target. The service owns one and relays by stat name, which also means a
  // keybind addresses the card it wants: `omarchy-shell sysmon toggle memory`.
  signal panelRequest(string stat, string action)

  IpcHandler {
    target: "sysmon"

    function open(stat: string): void { root.panelRequest(String(stat || ""), "open") }
    function close(stat: string): void { root.panelRequest(String(stat || ""), "close") }
    function toggle(stat: string): void { root.panelRequest(String(stat || ""), "toggle") }
  }

  // ---- sampler -------------------------------------------------------------

  // Previous /proc/stat totals, for the delta the percentages come from. The
  // sample interval is the measurement window, so no sleep is needed.
  property var _prevCpu: null
  property var _fanReadings: ({})

  signal fanSample()

  readonly property string discoverScript: String(Qt.resolvedUrl("scripts/sysmon-discover")).replace(/^file:\/\//, "")

  function sample() {
    statFile.reload()
    sampleCpu(statFile.text())
    memFile.reload()
    sampleMem(memFile.text())
    loadFile.reload()
    sampleLoad(loadFile.text())
    sampleFrequency()

    if (tempPath.length > 0) {
      tempFile.reload()
      tempC = parseMilliC(tempFile.text())
    } else {
      tempC = -1
    }

    _fanReadings = ({})
    fanSample()
    var nextFans = []
    var firstRpm = -1
    for (var i = 0; i < fanSources.length; i++) {
      var rpm = _fanReadings[fanSources[i].path]
      if (rpm === undefined || rpm < 0) continue
      nextFans.push({ "rpm": rpm, "label": fanSources[i].label })
      if (firstRpm < 0 && rpm > 0) firstRpm = rpm
    }
    // Every fan reading at zero is still a reading: report 0, not "no data".
    if (firstRpm < 0 && nextFans.length > 0) firstRpm = 0
    fans = nextFans
    fanRpm = firstRpm

    sampleGpu()

    cpuHistory = pushHistory(cpuHistory, cpuPercent)
    memHistory = pushHistory(memHistory, memPercent)
    gpuHistory = pushHistory(gpuHistory, gpuPercent)
  }

  // Every GPU file is a single number. A file the driver lacks reads empty,
  // so each value falls back to -1 on its own rather than blanking the rest.
  function readNumber(view) {
    view.reload()
    var v = parseFloat(String(view.text() || "").trim())
    return isNaN(v) ? -1 : v
  }

  function sampleGpu() {
    if (gpuDevice.length === 0) {
      gpuPercent = -1
      gpuVideoPercent = -1
      gpuVramUsed = -1
      gpuVramTotal = -1
      gpuGttUsed = -1
      gpuGttTotal = -1
      gpuTempC = -1
      gpuPowerW = -1
      gpuClockMhz = -1
      return
    }
    var busy = readNumber(gpuBusyFile)
    gpuPercent = busy >= 0 ? Math.round(Math.min(100, busy)) : -1
    var video = readNumber(gpuVideoFile)
    gpuVideoPercent = video >= 0 ? Math.round(Math.min(100, video)) : -1
    gpuVramUsed = readNumber(gpuVramUsedFile)
    gpuVramTotal = readNumber(gpuVramTotalFile)
    gpuGttUsed = readNumber(gpuGttUsedFile)
    gpuGttTotal = readNumber(gpuGttTotalFile)

    if (gpuTempPath.length > 0) {
      gpuTempFile.reload()
      gpuTempC = parseMilliC(gpuTempFile.text())
    } else {
      gpuTempC = -1
    }
    // hwmon power is microwatts, the clock is hertz.
    var uw = gpuPowerPath.length > 0 ? readNumber(gpuPowerFile) : -1
    gpuPowerW = uw >= 0 ? uw / 1e6 : -1
    var hz = gpuClockPath.length > 0 ? readNumber(gpuClockFile) : -1
    gpuClockMhz = hz > 0 ? Math.round(hz / 1e6) : -1
  }

  function sampleCpu(text) {
    var lines = String(text || "").split("\n")
    var vals = ({})
    var order = []
    for (var i = 0; i < lines.length; i++) {
      var tokens = lines[i].trim().split(/\s+/)
      if (!tokens[0] || tokens[0].indexOf("cpu") !== 0) continue
      // user nice system idle iowait irq softirq
      var total = 0
      for (var j = 1; j <= 7 && j < tokens.length; j++)
        total += parseInt(tokens[j]) || 0
      vals[tokens[0]] = { "total": total, "idle": parseInt(tokens[4]) || 0 }
      order.push(tokens[0])
    }
    var prev = _prevCpu
    _prevCpu = { "vals": vals, "order": order }
    if (!prev) return // first snapshot: nothing to diff against yet
    var cores = []
    var agg = -1
    for (var k = 0; k < order.length; k++) {
      var name = order[k]
      var was = prev.vals[name]
      if (!was) continue
      var dt = vals[name].total - was.total
      var di = vals[name].idle - was.idle
      var pct = dt > 0 ? Math.floor((100 * (dt - di)) / dt) : -1
      if (name === "cpu") agg = pct
      else cores.push(pct)
    }
    cpuPercent = agg
    cpuCores = cores
  }

  function sampleMem(text) {
    var fields = ({})
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^(\w+):\s+(\d+)/)
      if (match) fields[match[1]] = parseInt(match[2])
    }
    var total = fields.MemTotal || 0
    var avail = fields.MemAvailable || 0
    if (total <= 0) return
    memTotalKb = total
    memAvailableKb = avail
    memUsedKb = total - avail
    memFreeKb = fields.MemFree || 0
    memCachedKb = fields.Cached || 0
    memBuffersKb = fields.Buffers || 0
    swapTotalKb = fields.SwapTotal || 0
    swapUsedKb = (fields.SwapTotal || 0) - (fields.SwapFree || 0)
    memPercent = Math.floor(((total - avail) * 100) / total)
  }

  function sampleLoad(text) {
    var parts = String(text || "").trim().split(/\s+/)
    loadOne = parts.length > 0 ? parseFloat(parts[0]) : -1
    loadFive = parts.length > 1 ? parseFloat(parts[1]) : -1
    loadFifteen = parts.length > 2 ? parseFloat(parts[2]) : -1
  }

  // policy0's current frequency is the primary source; /proc/cpuinfo keeps the
  // value available on systems without the cpufreq sysfs interface.
  function sampleFrequency() {
    frequencyFile.reload()
    var khz = parseFloat(String(frequencyFile.text()).trim())
    if (!isNaN(khz) && khz > 0) {
      cpuFrequencyMhz = Math.round(khz / 1000)
      return
    }
    cpuInfoFile.reload()
    var match = String(cpuInfoFile.text() || "").match(/^cpu MHz\s*:\s*([0-9.]+)/m)
    var mhz = match ? parseFloat(match[1]) : NaN
    cpuFrequencyMhz = !isNaN(mhz) && mhz > 0 ? Math.round(mhz) : -1
  }

  // millidegrees -> °C, with a sanity window that rejects placeholder values.
  function parseMilliC(text) {
    var v = parseInt(String(text || "").trim())
    if (isNaN(v)) return -1
    var c = Math.floor(v / 1000)
    return (c > 0 && c < 130) ? c : -1
  }

  function parseCount(text) {
    var v = parseInt(String(text || "").trim())
    return isNaN(v) ? -1 : v
  }

  // Append one sample, keeping the last 60; unavailable (-1) plots as 0.
  function pushHistory(arr, value) {
    var next = (arr || []).slice(-59)
    next.push(value < 0 ? 0 : value)
    return next
  }

  // ---- sysfs sources picked by the slow poll's discovery pass --------------

  property var fanSources: [] // [{path, label}]

  property string gpuDevice: ""
  property string gpuCard: ""
  property string gpuDriver: ""
  property string gpuTempPath: ""
  property string gpuPowerPath: ""
  property string gpuClockPath: ""
  property string gpuPowerLabel: ""

  function applySlow(text) {
    var lines = String(text || "").trim().split(/\n+/)
    var nextTemp = ""
    var nextFans = []
    var nextDisks = []
    var nextGpu = { "device": "", "card": "", "driver": "", "temp": "", "power": "", "clock": "", "powerLabel": "" }
    for (var i = 0; i < lines.length; i++) {
      var tokens = lines[i].trim().split(/\s+/)
      if (tokens[0] === "temp" && tokens.length >= 2) {
        nextTemp = tokens[1]
      } else if (tokens[0] === "fan" && tokens.length >= 3) {
        nextFans.push({ "path": tokens[1], "label": tokens.slice(2).join(" ") })
      } else if (tokens[0] === "diskfs" && tokens.length >= 7) {
        nextDisks.push({
          "percent": parseInt(tokens[1]),
          "usedKb": parseInt(tokens[2]),
          "freeKb": parseInt(tokens[3]),
          "totalKb": parseInt(tokens[4]),
          "device": tokens[5],
          "mount": tokens.slice(6).join(" ")
        })
      } else if (tokens[0] === "gpu" && tokens.length >= 4) {
        nextGpu.device = tokens[1]
        nextGpu.card = tokens[2]
        nextGpu.driver = tokens[3]
      } else if (tokens[0] === "gpuhwmon" && tokens.length >= 5) {
        nextGpu.temp = tokens[1] === "-" ? "" : tokens[1]
        nextGpu.power = tokens[2] === "-" ? "" : tokens[2]
        nextGpu.clock = tokens[3] === "-" ? "" : tokens[3]
        nextGpu.powerLabel = tokens.slice(4).join(" ")
      }
    }
    tempPath = nextTemp
    // Only rebuild the fan readers when the hardware actually changed.
    if (JSON.stringify(nextFans) !== JSON.stringify(fanSources)) fanSources = nextFans
    disks = nextDisks
    gpuDevice = nextGpu.device
    gpuCard = nextGpu.card
    gpuDriver = nextGpu.driver
    gpuTempPath = nextGpu.temp
    gpuPowerPath = nextGpu.power
    gpuClockPath = nextGpu.clock
    gpuPowerLabel = nextGpu.powerLabel
  }

  function gpuFile(name) {
    return gpuDevice.length > 0 ? gpuDevice + "/" + name : ""
  }

  // ---- readers -------------------------------------------------------------

  FileView { id: statFile; path: "/proc/stat"; blockAllReads: true; printErrors: false }
  FileView { id: memFile; path: "/proc/meminfo"; blockAllReads: true; printErrors: false }
  FileView { id: loadFile; path: "/proc/loadavg"; blockAllReads: true; printErrors: false }
  FileView {
    id: frequencyFile
    path: "/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq"
    blockAllReads: true
    printErrors: false
  }
  FileView { id: cpuInfoFile; path: "/proc/cpuinfo"; blockAllReads: true; printErrors: false }
  FileView { id: tempFile; path: root.tempPath; blockAllReads: true; printErrors: false }

  FileView { id: gpuBusyFile; path: root.gpuFile("gpu_busy_percent"); blockAllReads: true; printErrors: false }
  FileView { id: gpuVideoFile; path: root.gpuFile("vcn_busy_percent"); blockAllReads: true; printErrors: false }
  FileView { id: gpuVramUsedFile; path: root.gpuFile("mem_info_vram_used"); blockAllReads: true; printErrors: false }
  FileView { id: gpuVramTotalFile; path: root.gpuFile("mem_info_vram_total"); blockAllReads: true; printErrors: false }
  FileView { id: gpuGttUsedFile; path: root.gpuFile("mem_info_gtt_used"); blockAllReads: true; printErrors: false }
  FileView { id: gpuGttTotalFile; path: root.gpuFile("mem_info_gtt_total"); blockAllReads: true; printErrors: false }
  FileView { id: gpuTempFile; path: root.gpuTempPath; blockAllReads: true; printErrors: false }
  FileView { id: gpuPowerFile; path: root.gpuPowerPath; blockAllReads: true; printErrors: false }
  FileView { id: gpuClockFile; path: root.gpuClockPath; blockAllReads: true; printErrors: false }

  // One reader per discovered fan; the fanSample signal fans out a synchronous
  // reload+report to each, so sample() can collect them in source order.
  Variants {
    model: root.fanSources

    Scope {
      id: fanScope
      required property var modelData

      FileView {
        id: fanFile
        path: fanScope.modelData.path
        blockAllReads: true
        printErrors: false
      }

      Connections {
        target: root
        function onFanSample() {
          fanFile.reload()
          root._fanReadings[fanScope.modelData.path] = root.parseCount(fanFile.text())
        }
      }
    }
  }

  Process {
    id: discoverProc
    command: ["sh", root.discoverScript]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySlow(text) }
  }

  Timer {
    id: fastPoll
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.sample()
  }

  Timer {
    id: slowPoll
    interval: root.viewers > 0 ? 5000 : 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!discoverProc.running) discoverProc.running = true
  }

  // The first /proc/stat delta needs a second snapshot; take it quickly rather
  // than leaving every pill blank for a full interval.
  Timer {
    id: primeTimer
    interval: 600
    onTriggered: root.sample()
  }

  Component.onCompleted: {
    sample()
    primeTimer.start()
  }
}
