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

Left click opens the card, right click opens `btop`.

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

The GPU is the first DRM card whose driver exposes `gpu_busy_percent` (amdgpu
does; i915, xe, and nvidia do not). Its `mem_info_vram_*`, `mem_info_gtt_*`,
and `vcn_busy_percent` sit beside it, and its own hwmon gives temperature,
power, and the shader clock. On an APU the only power sensor is `PPT`, the
whole package, so the card labels it "Package" rather than claiming it as GPU
power. The NPU (`amdxdna`) has no busy file at all, which is why there is no
NPU stat.

## Editing it

Saving a file here hot-reloads the plugin, which is enough for phrases,
colors, and card content. It does **not** re-instantiate the bar widgets, so
anything that changes a pill's own size — `pillPadding`, `meterGap`,
`meterThickness` — only shows up after `omarchy restart shell`.
