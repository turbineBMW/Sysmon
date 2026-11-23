# turbinebmw.sysmon

System-monitor pills for the Omarchy bar, ported from willshell's
`modules/bar/widgets/SystemMonitor.qml` and `services/SystemStatsService.qml`.

Each pill keeps willshell's look on the bar — a glyph with a thin meter beside
it that fills from the bottom — and swaps willshell's applet popup for an
Omarchy card built the same way `omarchy.power` builds the battery panel: a
hero line with the glyph, the title, a rotating status phrase, and the value;
then a headline meter; then the detail.

## Stats

| `stat`        | Icon | Card shows |
|---------------|------|------------|
| `cpu`         | chip with pins | Frequency, core count, load averages, a per-core meter grid |
| `gpu`         | dual-fan card | Shader clock, temperature, video engine, power, device, VRAM and shared (GTT) memory meters |
| `temperature` | thermometer | Sensor, current fan speed, warning and critical points |
| `memory`      | memory module | Used / available / free / cached / buffers / total, plus swap |
| `fan`         | four skewed blades | One metered row per discovered hwmon fan |
| `disk`        | drive with platter | One metered row per real filesystem |

## Icons

The artwork is ours, in `Icons.js`, as SVG path data on a shared 24x24 grid,
rendered through `QtQuick.Shapes` so it takes the theme foreground directly
and stays crisp at any scale.

Nerd Font glyphs came first and were the wrong call: the bar's other icons
(bluetooth, wi-fi, monitor, battery) are clean silhouettes on ~1px strokes,
and MDI's `cpu-64-bit` and `memory` carry enough fine detail that at 13px
they turned to mush beside them.

Two rules keep a seventh icon consistent with these six:

- draw inside the live area, `2..22` on both axes, with 2.2-unit strokes
- declare the art's real height in `ART_HEIGHT`; `StatIcon` scales every icon
  so that height lands on the same painted pixels. A shared viewBox is not
  enough — a short, wide drawing and a full-height one would not match.

Subpaths wind clockwise, holes wind counter-clockwise, and the shape uses
`WindingFill`, so overlapping parts union instead of cancelling out the way
they would under `OddEvenFill`.

## Status phrases

Every stat has three phrase pools — calm, busy, alarm — picked by the same
0..1 ratio the meter draws, and rotated on a fade while the card is open. A
CPU goes from "Twiddling thumbs" through "Chewing cycles" to "All cores
screaming"; a disk from "Room to roam" to "Time to delete something". They
live in `Model.js` and are meant to be edited.

## Layout

The plugin is `allowMultiple`, so one entry per stat goes in
`~/.config/omarchy/shell.json`:

```json
{ "id": "turbinebmw.sysmon", "stat": "cpu" },
{ "id": "turbinebmw.sysmon", "stat": "gpu" },
{ "id": "turbinebmw.sysmon", "stat": "temperature" },
{ "id": "turbinebmw.sysmon", "stat": "memory" },
{ "id": "turbinebmw.sysmon", "stat": "fan" },
{ "id": "turbinebmw.sysmon", "stat": "disk", "mount": "/" }
```

Per-entry settings: `stat`, `mount` (disk only), `fanMaxRpm` (fan only, the
RPM the meter treats as full scale), `warningThreshold` and
`criticalThreshold` (percent).

Left click opens the card. Right click opens the pill menu: a checklist of
the six stats, then an "Open btop" button.

## Pill menu

A bar widget cannot rewrite the bar layout. The shell only gives
`mutateShellConfig` to kind `bar` plugins, and `updateEntryInline` rewrites
every entry with the same id, which would turn all the pills into one stat.
`omarchy bar put` leaves a widget that is already on the bar alone, so it
cannot add a second pill either.

So ticking a stat runs `scripts/sysmon-pills <stat> on|off`, which edits
`shell.json` through `omarchy-shell-config`'s `commit`, the same atomic
write-and-reload the `omarchy bar` commands use. It:

- adds a new pill to the section the other pills are in, in menu order
- removes every pill for that stat
- refuses to remove the last pill, because that pill is the only way back
  into the menu
- takes a lock, so quick clicks cannot race on the file

The menu reads which stats are on the bar from `bar.layoutConfig`, so every
pill's menu matches the bar. While one change is in flight the menu ignores
further clicks, until the layout updates or 4s pass.

## Bar height

These pills are sized from `Style.bar.iconCanvas`, so they follow the bar.
The bar's own height is not this plugin's to set — it lives in
`~/.config/omarchy/shell.toml`, which overrides the theme and survives theme
switches:

```toml
[bar]
size-horizontal = 18
```

## Keybinds

Each pill is a separate widget instance, so they cannot each own an IPC
target. The service owns one and relays by stat name:

```bash
omarchy-shell sysmon toggle memory
omarchy-shell sysmon open cpu
omarchy-shell sysmon close cpu
```

Passing no stat addresses every card at once.

## How it samples

`Service.qml` is a `service`-kind plugin mounted once, no matter how many
pills are on the bar. The fast path spawns no processes: `/proc/stat`,
`/proc/meminfo`, `/proc/loadavg`, cpufreq, the thermal sensor, each fan, and
the GPU's sysfs files are read in-process through `FileView` every 2s.
`scripts/sysmon-discover` runs every 30s (5s while a card is open) to run `df`
and to find *where* the thermal sensor, fans, and GPU live, so hardware that
appears late still gets picked up.

## GPU

`sysmon-discover` picks one GPU and says how to read it:

- **AMD (`amdgpu`)**, preferred when present: the device's own
  `gpu_busy_percent`, with `vcn_busy_percent`, `mem_info_vram_*` and
  `mem_info_gtt_*` beside it, and its hwmon for temperature, power, and the
  shader clock. On an APU the only power sensor is `PPT`, the whole package,
  so the card labels it "Package" rather than claiming it as GPU power.
- **Intel (`i915`, `xe`) and Qualcomm (`msm`)** have no busy file. They report
  busy time per client in `/proc/<pid>/fdinfo` (the kernel's
  drm-usage-stats), and `scripts/sysmon-gpu-busy` adds that up. Busy is the
  busiest non-video engine, video the busiest video engine, the same split
  amdgpu makes. Intel's clock is the GT frequency in MHz (0 while the GT
  sleeps); Qualcomm's comes from the GPU's devfreq, and its temperature from
  the hottest `gpuss-*` thermal zone. Neither reports memory totals.
- **NVIDIA** has neither, so it gets no reading.

The fdinfo reader runs as one long-lived process, started only while a GPU
pill is on the bar (pills register with `setGpuUser`). Finding the GPU's
files means a stat of every open fd on the system, so it does that in full
every 30s and in between only for processes that appeared since the last
sample; a new app counts from its next sample. It sees only processes this
user can read, which on a desktop is nearly all GPU work. It costs about 8ms
of CPU per 2s sample on a Snapdragon X Elite with ~2500 open fds.

The NPU (`amdxdna`, Qualcomm's Hexagon) has no usage counter at all, which is
why there is no NPU stat.

## Tests

`tests/discover-gpu` checks which GPU discovery picks on fake AMD, Intel, and
Qualcomm sysfs trees (`SYSMON_SYSFS_ROOT`). `tests/gpu-busy` checks the fdinfo
reader against fake i915 and xe clients (`SYSMON_PROC_ROOT`,
`SYSMON_DEV_ROOT`), so the Intel paths run on any machine.
`tests/discover-temp` checks the CPU temperature pick and that discovery never
opens a sensor it does not need: reading a speaker amp's (wsa884x) hwmon
temperature wakes the amp and its SoundWire bus, and discovery runs every 30s.

## Editing it

Saving a file here hot-reloads the plugin, which is enough for phrases,
colors, and card content. It does **not** re-instantiate the bar widgets, so
anything that changes a pill's own size — `pillPadding`, `meterGap`,
`meterThickness` — only shows up after `omarchy restart shell`.
