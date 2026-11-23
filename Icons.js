// Hand-drawn icon set for the system-monitor pills, as SVG path data on a
// shared 24x24 grid.
//
// Why not Nerd Font glyphs: the bar's other icons (bluetooth, wi-fi, monitor,
// battery) are clean silhouettes drawn with ~2-unit strokes, and at the 13px
// the bar renders them at, MDI's `cpu-64-bit` and `memory` are fussy enough
// that their detail turns to mush beside them. Drawing our own means one
// stroke weight, one live area, and one optical height across all six.
//
// Conventions, so a sixth icon added later still matches:
//   * live area is 2..22 on both axes — art fills it, nothing bleeds past
//   * strokes are 2.2 units, which lands on ~1 device pixel at bar size
//   * subpaths wind clockwise; holes wind counter-clockwise and the shape is
//     filled with WindingFill, so overlapping parts union instead of
//     cancelling each other out the way OddEvenFill would

// Clockwise rounded rectangle.
function rr(x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2)
  return "M" + (x + r) + " " + y +
    " H" + (x + w - r) + " A" + r + " " + r + " 0 0 1 " + (x + w) + " " + (y + r) +
    " V" + (y + h - r) + " A" + r + " " + r + " 0 0 1 " + (x + w - r) + " " + (y + h) +
    " H" + (x + r) + " A" + r + " " + r + " 0 0 1 " + x + " " + (y + h - r) +
    " V" + (y + r) + " A" + r + " " + r + " 0 0 1 " + (x + r) + " " + y + " Z"
}

// Counter-clockwise rounded rectangle — punches a hole in an enclosing shape.
function rrHole(x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2)
  return "M" + (x + r) + " " + y +
    " A" + r + " " + r + " 0 0 0 " + x + " " + (y + r) +
    " V" + (y + h - r) + " A" + r + " " + r + " 0 0 0 " + (x + r) + " " + (y + h) +
    " H" + (x + w - r) + " A" + r + " " + r + " 0 0 0 " + (x + w) + " " + (y + h - r) +
    " V" + (y + r) + " A" + r + " " + r + " 0 0 0 " + (x + w - r) + " " + y + " Z"
}

function circ(cx, cy, r) {
  return "M" + (cx - r) + " " + cy +
    " A" + r + " " + r + " 0 1 1 " + (cx + r) + " " + cy +
    " A" + r + " " + r + " 0 1 1 " + (cx - r) + " " + cy + " Z"
}

function circHole(cx, cy, r) {
  return "M" + (cx - r) + " " + cy +
    " A" + r + " " + r + " 0 1 0 " + (cx + r) + " " + cy +
    " A" + r + " " + r + " 0 1 0 " + (cx - r) + " " + cy + " Z"
}

// One fan blade: a round tip with a wedge back to the hub, set at an angle to
// the spoke so the four of them read as rotation rather than as a flower.
function blade(degrees) {
  var skew = 24
  var ang = (degrees + skew) * Math.PI / 180
  var dist = 6.0
  var r = 3.7
  var cx = 12 + dist * Math.cos(ang)
  var cy = 12 + dist * Math.sin(ang)
  var px = -Math.sin(ang) * r
  var py = Math.cos(ang) * r
  return "M12 12 L" + (cx - px) + " " + (cy - py) +
    " A" + r + " " + r + " 0 1 1 " + (cx + px) + " " + (cy + py) + " Z"
}

// Art height in grid units, per icon. The renderer scales each icon so these
// all land on the same painted height, which is what actually reads as
// "consistent" — a shared viewBox alone would not.
var ART_HEIGHT = {
  cpu: 20,
  // Board top to the tips of the edge connector.
  gpu: 19,
  temperature: 20,
  // The module is turned upright when rendered, making its 20-unit width
  // the painted height.
  memory: 20,
  // The blade tips are round, so the art stops just short of the live area.
  fan: 19.4,
  disk: 20
}

function artHeight(stat) {
  var h = ART_HEIGHT[String(stat || "")]
  return h === undefined ? 20 : h
}

function pathFor(stat) {
  switch (String(stat || "")) {

  // Chip: pins, a square die outline, a solid core.
  case "cpu":
    return [
      rr(8.3, 2, 2.4, 3.6, 1), rr(13.3, 2, 2.4, 3.6, 1),
      rr(8.3, 18.4, 2.4, 3.6, 1), rr(13.3, 18.4, 2.4, 3.6, 1),
      rr(2, 8.3, 3.6, 2.4, 1), rr(2, 13.3, 3.6, 2.4, 1),
      rr(18.4, 8.3, 3.6, 2.4, 1), rr(18.4, 13.3, 3.6, 2.4, 1),
      rr(5.5, 5.5, 13, 13, 2.6), rrHole(7.7, 7.7, 8.6, 8.6, 1.5),
      rr(10, 10, 4, 4, 1)
    ].join(" ")

  // Graphics card seen face-on: an outlined shroud holding two fans, each a
  // solid disc with its hub bored out, and the PCIe edge connector below,
  // split by its key. Two fans is what tells it apart from the drive's
  // single platter.
  case "gpu":
    return [
      rr(2, 2.5, 20, 14, 2.5), rrHole(4.2, 4.7, 15.6, 9.6, 1.5),
      circ(8.3, 9.5, 3.3), circHole(8.3, 9.5, 1.1),
      circ(15.7, 9.5, 3.3), circHole(15.7, 9.5, 1.1),
      rr(4.6, 15, 3.4, 6.5, 0.8), rr(9.4, 15, 9.2, 6.5, 0.8)
    ].join(" ")

  // Thermometer: a solid stem running into a solid bulb. Wider than MDI's so
  // it carries the same visual weight as the chip beside it.
  case "temperature":
    return [
      rr(9.2, 2, 5.6, 13, 2.8),
      circ(12, 17, 5)
    ].join(" ")

  // Memory module seen face-on: body outline, the keying notch bitten out of
  // its bottom edge, and four contacts below. The notch is a hole rather than
  // a filled tab — as a tab it bridged the body and read as a slot.
  case "memory":
    return [
      rr(2, 3.5, 20, 11.5, 2), rrHole(4.2, 5.7, 15.6, 7.1, 1.2),
      rrHole(10.9, 12.2, 2.2, 2.8, 0.4),
      rr(4.4, 15.5, 2.6, 5, 0.8), rr(9.1, 15.5, 2.6, 5, 0.8),
      rr(13.8, 15.5, 2.6, 5, 0.8), rr(18.5, 15.5, 2.6, 5, 0.8)
    ].join(" ")

  // Four skewed blades around a hub.
  case "fan":
    return [
      blade(-90), blade(0), blade(90), blade(180),
      circ(12, 12, 2.4)
    ].join(" ")

  // Narrow drive body with a lighter platter ring and an activity light.
  // Its full-height outline keeps the same painted height as the other art.
  case "disk":
    return [
      rr(3.5, 2, 17, 20, 2.5), rrHole(5.5, 4, 13, 16, 1.5),
      circ(10.8, 10.7, 4), circHole(10.8, 10.7, 2.2),
      circ(16.4, 17.1, 1.1)
    ].join(" ")
  }
  return ""
}
