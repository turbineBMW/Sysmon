import QtQuick
import QtQuick.Shapes
import "Icons.js" as Icons

// Renders one icon from Icons.js at a given painted height.
//
// `inkHeight` is the height of the drawing itself, not of the box around it.
// Each icon declares its own art height in grid units and is scaled to hit
// this number. The memory module turns upright to match the other glyphs.
Item {
  id: root

  property string stat: "cpu"
  property color color: "white"
  property real inkHeight: 11

  readonly property real unit: inkHeight / Icons.artHeight(stat)

  implicitWidth: 24 * unit
  implicitHeight: 24 * unit

  Shape {
    anchors.centerIn: parent
    width: 24
    height: 24
    scale: root.unit
    rotation: root.stat === "memory" ? 90 : 0
    // The curve renderer antialiases in the fragment shader, which is what
    // keeps a 2-unit stroke from crawling once it is scaled down to about one
    // device pixel.
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      strokeWidth: 0
      fillRule: ShapePath.WindingFill
      PathSvg { path: Icons.pathFor(root.stat) }
    }
  }
}
