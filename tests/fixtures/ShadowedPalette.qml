import QtQuick

// Deliberately broken: the id "palette" resolves to Item.palette inside the
// delegate, so the swatches get width 0. tests/lint-qml.py must reject this.
Item {
  Row {
    id: palette
    readonly property real swatch: 22
    Repeater {
      model: 3
      Rectangle { width: palette.swatch; height: palette.swatch }
    }
  }
}
