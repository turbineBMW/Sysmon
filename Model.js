// Stat definitions, the rotating status phrases, and formatting helpers for
// the system-monitor pills. The artwork lives in Icons.js.
//
// Each stat owns three phrase tiers keyed off the same 0..1 ratio the bar
// meter draws, so what the card says and what the meter shows never disagree.
// The tone follows omarchy.power's battery hero ("Slurping power", "Spending
// joules"): a machine narrating its own effort.

var STATS = {
  cpu: {
    title: "Processor",
    unit: "%",
    // A pegged CPU is loud but normal, so the alarm sits at the usual 75/90.
    calm: [
      "Twiddling thumbs",
      "Counting sheep",
      "Idling in neutral",
      "Awaiting orders",
      "Politely bored",
      "Coasting downhill"
    ],
    busy: [
      "Chewing cycles",
      "Crunching numbers",
      "Grinding instructions",
      "Munching threads",
      "Shuffling registers",
      "Devouring work",
      "Spinning up a sweat"
    ],
    alarm: [
      "All cores screaming",
      "Melting silicon",
      "Redlining",
      "Pegged to the floor",
      "Boiling the scheduler",
      "Every thread on fire"
    ]
  },
  temperature: {
    title: "CPU temperature",
    unit: "°",
    calm: [
      "Cool as a cucumber",
      "Running chilly",
      "Comfortably tepid",
      "Room temperature-ish",
      "Nothing to fan about"
    ],
    busy: [
      "Working up a sweat",
      "Getting toasty",
      "Warm to the touch",
      "Radiating gently",
      "Shedding joules"
    ],
    alarm: [
      "Toasting marshmallows",
      "Baking the die",
      "Approaching lava",
      "Thermal drama",
      "Searing the paste"
    ]
  },
  memory: {
    title: "Memory",
    unit: "%",
    calm: [
      "Acres of RAM",
      "Pages to spare",
      "Plenty of headroom",
      "Half-empty shelves",
      "Loafing in cache"
    ],
    busy: [
      "Stacking pages",
      "Filling the shelves",
      "Hoarding bytes",
      "Packing gigabytes",
      "Squirrelling away"
    ],
    alarm: [
      "Elbow to elbow",
      "Gigabytes gasping",
      "Swap is circling",
      "Out of shelf space",
      "The OOM killer stirs"
    ]
  },
  fan: {
    title: "Cooling",
    unit: " RPM",
    calm: [
      "Silent running",
      "Barely breathing",
      "Holding its breath",
      "Lazy Sunday spin",
      "Idling on the breeze"
    ],
    busy: [
      "Moving air",
      "Whirring along",
      "Pushing a breeze",
      "Working the blades",
      "Exhaling warmth"
    ],
    alarm: [
      "Screaming for air",
      "Full gale",
      "Jet on the desk",
      "Achieving lift",
      "Hovering imminent"
    ]
  },
  disk: {
    title: "Storage",
    unit: "%",
    calm: [
      "Room to roam",
      "Empty shelves",
      "Acres of platter",
      "Barely unpacked",
      "Space to spare"
    ],
    busy: [
      "Stacking crates",
      "Filling the shelves",
      "Getting cozy",
      "Boxes in the hallway",
      "Packing it in"
    ],
    alarm: [
      "Scraping the platter",
      "Crumbs left",
      "Nearly wedged",
      "One download from doom",
      "Time to delete something"
    ]
  }
}

function statDef(stat) {
  return STATS[String(stat || "")] || STATS.cpu
}

function statIds() {
  return ["cpu", "temperature", "memory", "fan", "disk"]
}

// Pick a tier from the same ratio the meter draws, then a phrase within it.
// The index is rotated by the caller's timer, so a tier change is visible
// immediately while a steady state keeps cycling its own pool.
function phraseFor(stat, ratio, warnRatio, critRatio, index) {
  var def = statDef(stat)
  var pool = def.calm
  if (ratio >= critRatio) pool = def.alarm
  else if (ratio >= warnRatio) pool = def.busy
  if (!pool || pool.length === 0) return ""
  var i = Math.abs(Math.floor(index || 0)) % pool.length
  return pool[i]
}

function phraseCount(stat, ratio, warnRatio, critRatio) {
  var def = statDef(stat)
  if (ratio >= critRatio) return def.alarm.length
  if (ratio >= warnRatio) return def.busy.length
  return def.calm.length
}

function clamp(value, lo, hi) {
  return Math.max(lo, Math.min(hi, value))
}

function formatKb(kb) {
  if (kb === undefined || kb === null || kb < 0) return "—"
  var gib = kb / 1024 / 1024
  if (gib >= 1) return gib.toFixed(1) + " GiB"
  return Math.round(kb / 1024) + " MiB"
}

function formatMhz(mhz) {
  if (mhz === undefined || mhz < 0) return "—"
  if (mhz >= 1000) return (mhz / 1000).toFixed(2) + " GHz"
  return Math.round(mhz) + " MHz"
}

function formatRpm(rpm) {
  if (rpm === undefined || rpm < 0) return "—"
  return rpm + " RPM"
}

// The bar meter has no room for a number, so the tooltip carries it.
function shortValue(stat, service, mount) {
  switch (String(stat)) {
  case "temperature":
    return service.tempC >= 0 ? service.tempC + "°C" : "—"
  case "memory":
    return service.memPercent >= 0 ? service.memPercent + "%" : "—"
  case "fan":
    return service.fanRpm >= 0 ? formatRpm(service.fanRpm) : "—"
  case "disk":
    var pct = diskPercentFor(service, mount)
    return pct >= 0 ? pct + "%" : "—"
  default:
    return service.cpuPercent >= 0 ? service.cpuPercent + "%" : "—"
  }
}

function diskEntryFor(service, mount) {
  var wanted = String(mount || "/")
  var disks = service.disks || []
  for (var i = 0; i < disks.length; i++)
    if (String(disks[i].mount) === wanted) return disks[i]
  return disks.length > 0 ? disks[0] : null
}

function diskPercentFor(service, mount) {
  var entry = diskEntryFor(service, mount)
  return entry ? entry.percent : -1
}

// Sensor paths are long and the card only has room for the interesting tail:
// /sys/class/hwmon/hwmon5/temp1_input -> hwmon5/temp1.
function sensorLabel(path) {
  var s = String(path || "")
  if (s.length === 0) return "—"
  var parts = s.split("/")
  var leaf = parts[parts.length - 1].replace(/_input$/, "")
  var parent = parts.length > 1 ? parts[parts.length - 2] : ""
  return parent ? parent + "/" + leaf : leaf
}
