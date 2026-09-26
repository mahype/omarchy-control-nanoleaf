import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "I18n.js" as I18n

// Bar icon + popup. Holds no device state of its own — everything comes from
// the service; this file only decides what to show and forwards actions.
//
// Bar icon: left click opens the panel, right click toggles all devices,
// scrolling steps the brightness of all devices that are on.
Panel {
  id: root
  moduleName: "io.github.mahype.omarchy-control-nanoleaf"
  ipcTarget: "nanoleaf"

  // UI language: widget setting "language" (Auto | English | Deutsch); Auto
  // follows the system locale.
  readonly property string lang: I18n.resolve(setting("language", "Auto"), Qt.locale().name)
  function tr(key, arg) { return I18n.t(lang, key, arg) }

  readonly property var nl: bar && bar.shell ? bar.shell.serviceFor("io.github.mahype.omarchy-control-nanoleaf") : null
  readonly property bool ready: nl !== null
  readonly property var devices: ready ? nl.devices : []
  readonly property bool singleDevice: devices.length === 1

  // Only one device is expanded at a time; nothing stays expanded between opens.
  property string expandedId: ""

  // Profile UI state; reset when the panel closes.
  property bool savingProfile: false
  property string confirmDeleteId: ""
  readonly property var profiles: ready ? nl.profiles : []
  readonly property bool anyReachable: reachableDevices.length > 0

  // Devices ticked in the "save profile" form: id -> true.
  property var saveSelection: ({})
  readonly property var reachableDevices: {
    if (!ready) return []
    nl.revision
    return devices.filter(function(d) { return nl.stateFor(d.id).reachable })
  }

  function startSaving() {
    var sel = {}
    for (var i = 0; i < reachableDevices.length; i++) sel[reachableDevices[i].id] = true
    saveSelection = sel
    confirmDeleteId = ""
    savingProfile = true
  }

  function toggleSelected(id) {
    var sel = Object.assign({}, saveSelection)
    sel[id] = !sel[id]
    saveSelection = sel
  }

  function selectedIds() {
    return reachableDevices.map(function(d) { return d.id }).filter(function(id) { return saveSelection[id] === true })
  }

  // Typing the name of an existing profile preselects its devices, so
  // overwriting keeps the same device set unless changed.
  function preselectFor(name) {
    var p = ready ? nl.profileByName(name) : null
    if (!p) return
    var sel = {}
    for (var i = 0; i < reachableDevices.length; i++) {
      var id = reachableDevices[i].id
      sel[id] = p.devices[id] !== undefined
    }
    saveSelection = sel
  }

  function profileName(id) {
    for (var i = 0; i < profiles.length; i++) if (profiles[i].id === id) return profiles[i].name
    return ""
  }

  // Hexagon = the standard Shapes tile. The glyphs are pointy-top, so the bar
  // button rotates them 90° to rest on a flat edge.
  readonly property string iconOn: String.fromCodePoint(0xF02D8)      // hexagon
  readonly property string iconOff: String.fromCodePoint(0xF02D9)     // hexagon-outline
  readonly property string iconAdd: String.fromCodePoint(0xF0415)     // plus
  readonly property string iconExpand: String.fromCodePoint(0xF0140)  // chevron-down
  readonly property string iconCollapse: String.fromCodePoint(0xF0143)// chevron-up
  readonly property string iconSun: String.fromCodePoint(0xF00DF)     // brightness-6
  readonly property string iconIdentify: String.fromCodePoint(0xF0241)   // flash
  readonly property string iconChecked: String.fromCodePoint(0xF0132)    // checkbox-marked
  readonly property string iconUnchecked: String.fromCodePoint(0xF0131)  // checkbox-blank-outline

  // Quick colors for the "Farbe" mode (hue 0–360, sat 0–100).
  readonly property var colorPresets: [
    { h: 0, s: 100 }, { h: 28, s: 100 }, { h: 50, s: 100 }, { h: 120, s: 100 },
    { h: 175, s: 100 }, { h: 225, s: 100 }, { h: 275, s: 100 }, { h: 320, s: 100 }
  ]

  function tooltip() {
    if (!ready) return tr("serviceUnavailable")
    if (!nl.hasDevices) return tr("noDevice")
    return nl.anyOn ? tr("tooltipOn", nl.averageBrightness) : tr("tooltipOff")
  }

  onOpenedChanged: {
    if (!opened) {
      expandedId = ""
      savingProfile = false
      confirmDeleteId = ""
      if (ready) nl.missingScenes = []
      return
    }
    if (!ready) return
    nl.refresh()
    if (!nl.hasDevices) nl.discover()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.ready && root.nl.anyOn ? root.iconOn : root.iconOff
    textRotation: 90
    tooltipText: root.tooltip()
    onPressed: function(b) {
      if (b === Qt.RightButton && root.ready) root.nl.toggleAll()
      else if (b === Qt.LeftButton) root.toggle()
    }
    onWheelMoved: function(delta) {
      if (root.ready) root.nl.stepAllBrightness(delta > 0 ? 10 : -10)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Typing a profile name must not drive panel shortcuts.
      blocked: root.savingProfile
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Header: title · add · all on/off ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(title.implicitHeight, allSwitch.implicitHeight)

          Text {
            id: title
            textFormat: Text.PlainText
            text: "Nanoleaf"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            PanelActionButton {
              iconText: root.iconAdd
              tooltipText: root.tr("searchDevices")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              enabled: root.ready && !root.nl.discovering
              onClicked: root.nl.discover()
            }

            ToggleSwitch {
              id: allSwitch
              visible: root.devices.length > 1
              checked: root.ready && root.nl.anyOn
              foreground: root.bar.foreground
              anchors.verticalCenter: parent.verticalCenter
              onToggled: root.nl.toggleAll()
            }
          }
        }

        // ---------- Profiles ----------
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.profiles.length > 0

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                text: modelData.name
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                active: root.ready && root.nl.activeProfileId === modelData.id
                onClicked: {
                  root.confirmDeleteId = ""
                  root.nl.applyProfile(modelData.id)
                }

                // Right click asks to delete; left clicks pass through.
                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.RightButton
                  onClicked: root.confirmDeleteId = modelData.id
                }
              }
            }
          }

          Item {
            visible: root.confirmDeleteId !== ""
            width: parent.width
            implicitHeight: deleteBtn.implicitHeight

            HintText {
              text: root.tr("deleteProfileQuestion", root.profileName(root.confirmDeleteId))
              opacity: 1
              anchors.left: parent.left
              anchors.right: deleteRow.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              id: deleteRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Button {
                id: deleteBtn
                text: root.tr("delete")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: {
                  root.nl.deleteProfile(root.confirmDeleteId)
                  root.confirmDeleteId = ""
                }
              }

              Button {
                text: root.tr("cancel")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.confirmDeleteId = ""
              }
            }
          }

          HintText {
            visible: root.ready && root.nl.missingScenes.length > 0
            text: root.ready ? root.tr("sceneMissing", root.nl.missingScenes.join(", ")) : ""
            opacity: 1
          }
        }

        // ---------- Brightness for all (only with several devices) ----------
        BrightnessRow {
          visible: root.ready && root.devices.length > 1
          value: root.ready ? root.nl.averageBrightness : 0
          enabled: root.ready && root.nl.anyOn
          onCommitted: function(v) { root.nl.setAllBrightness(v) }
        }

        // ---------- Devices ----------
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.devices.length > 0

          Repeater {
            model: root.devices
            DeviceRow {
              required property var modelData
              device: modelData
              expanded: root.singleDevice || root.expandedId === modelData.id
              onExpandToggled: root.expandedId = root.expandedId === modelData.id ? "" : modelData.id
            }
          }
        }

        // ---------- Save current state as profile ----------
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.anyReachable

          PanelSeparator { foreground: root.bar.foreground }

          Button {
            visible: !root.savingProfile
            text: root.tr("saveAsProfile")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.startSaving()
          }

          Item {
            visible: root.savingProfile
            width: parent.width
            implicitHeight: nameField.implicitHeight

            TextField {
              id: nameField
              anchors.left: parent.left
              anchors.right: saveBtn.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: root.tr("profileName")
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlGap
              verticalPadding: Style.spacing.controlPaddingY
              onAccepted: saveBtn.save()
              onTextChanged: root.preselectFor(text)
              Keys.onEscapePressed: root.savingProfile = false
              onVisibleChanged: {
                if (visible) { text = ""; Qt.callLater(forceActiveFocus) }
              }
            }

            Button {
              id: saveBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("save")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              enabled: nameField.text.trim() !== "" && root.selectedIds().length > 0
              function save() {
                if (!enabled) return
                if (root.nl.saveProfile(nameField.text, root.selectedIds())) root.savingProfile = false
              }
              onClicked: save()
            }
          }

          // Which devices go into the profile (only shown with several).
          Column {
            visible: root.savingProfile && root.reachableDevices.length > 1
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.reachableDevices
              Item {
                required property var modelData
                readonly property bool checked: root.saveSelection[modelData.id] === true
                width: parent.width
                implicitHeight: Style.space(26)

                Text {
                  id: checkIcon
                  textFormat: Text.PlainText
                  text: parent.checked ? root.iconChecked : root.iconUnchecked
                  color: parent.checked ? Color.accent : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  anchors.left: checkIcon.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSelected(modelData.id)
                }
              }
            }
          }

          HintText {
            visible: root.savingProfile && root.ready && root.nl.profileByName(nameField.text) !== null
            text: root.tr("overwritesProfile")
          }
        }

        // ---------- Discovery / pairing ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.ready && (root.nl.discovered.length > 0 || root.nl.discovering || !root.nl.hasDevices)

          PanelSeparator { visible: root.devices.length > 0; foreground: root.bar.foreground }

          PanelSectionHeader {
            text: root.tr("newDevices")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          HintText {
            visible: root.ready && root.nl.discovering
            text: root.tr("searching")
          }

          HintText {
            visible: root.ready && !root.nl.discovering && root.nl.discovered.length === 0
            text: root.tr("noNewDevices")
          }

          HintText {
            visible: root.ready && root.nl.discovered.length > 0
            text: root.tr("pairHint")
          }

          Repeater {
            model: root.ready ? root.nl.discovered : []
            Item {
              required property var modelData
              width: column.width
              implicitHeight: pairButton.implicitHeight

              Text {
                textFormat: Text.PlainText
                text: modelData.name
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                anchors.left: parent.left
                anchors.right: pairButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Button {
                id: pairButton
                anchors.right: parent.right
                text: root.nl.pairingId === modelData.id ? root.tr("pairing") : root.tr("pair")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                enabled: root.nl.pairingId === ""
                onClicked: root.nl.pair(modelData.id)
              }
            }
          }

          HintText {
            visible: root.ready && root.nl.pairingError !== ""
            text: !root.ready || root.nl.pairingError === "" ? ""
              : root.tr(root.nl.pairingError === "not-pairing" ? "pairNotReady" : "pairUnreachable")
            color: root.bar.urgent !== undefined ? root.bar.urgent : root.bar.foreground
            opacity: 1
          }
        }
      }
    }
  }

  // ---------- Components ----------

  component HintText: Text {
    width: column.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component BrightnessRow: Item {
    id: bRow
    property real value: 0
    signal committed(real value)

    width: column.width
    implicitHeight: slider.implicitHeight
    opacity: enabled ? 1 : 0.4

    Text {
      id: sunIcon
      textFormat: Text.PlainText
      text: root.iconSun
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    PanelSlider {
      id: slider
      bar: root.bar
      minimum: 1
      maximum: 100
      step: 10
      integer: true
      value: bRow.value
      anchors.left: sunIcon.right
      anchors.leftMargin: Style.space(10)
      anchors.right: pct.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      // Send on release, not on every movement.
      onReleased: function(v) { bRow.committed(v) }
    }

    Text {
      id: pct
      textFormat: Text.PlainText
      text: Math.round(slider.liveValue) + " %"
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      width: Style.space(40)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // Slider on a colored gradient track (hue, color temperature). Commits on
  // release, like PanelSlider.
  component GradientSlider: Item {
    id: gs
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property var stops: []
    property real liveValue: value
    property bool dragging: false
    signal committed(real value)

    onValueChanged: if (!dragging) liveValue = value

    implicitHeight: Style.space(22)
    readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / Math.max(0.0001, maximum - minimum)))

    Canvas {
      id: gsTrack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(8)
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var g = ctx.createLinearGradient(0, 0, width, 0)
        var n = gs.stops.length
        for (var i = 0; i < n; i++) g.addColorStop(n > 1 ? i / (n - 1) : 0, String(gs.stops[i]))
        var r = height / 2
        ctx.beginPath()
        ctx.moveTo(r, 0)
        ctx.arcTo(width, 0, width, height, r)
        ctx.arcTo(width, height, 0, height, r)
        ctx.arcTo(0, height, 0, 0, r)
        ctx.arcTo(0, 0, width, 0, r)
        ctx.closePath()
        ctx.fillStyle = g
        ctx.fill()
      }
      onWidthChanged: requestPaint()
      Connections {
        target: gs
        function onStopsChanged() { gsTrack.requestPaint() }
      }
    }

    Rectangle {
      width: Style.space(16)
      height: width
      radius: width / 2
      color: "transparent"
      border.width: Math.max(2, Style.space(3))
      border.color: root.bar.foreground
      anchors.verticalCenter: gsTrack.verticalCenter
      x: Math.max(0, Math.min(gsTrack.width - width, gsTrack.width * gs.progress - width / 2))
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      function valueAt(x) {
        var p = Math.max(0, Math.min(1, x / Math.max(1, width)))
        return gs.minimum + p * (gs.maximum - gs.minimum)
      }
      onPressed: function(m) { gs.dragging = true; gs.liveValue = valueAt(m.x) }
      onPositionChanged: function(m) { if (gs.dragging) gs.liveValue = valueAt(m.x) }
      onReleased: { gs.dragging = false; gs.committed(gs.liveValue) }
    }
  }

  component DeviceRow: Column {
    id: dRow
    property var device: ({})
    property bool expanded: false
    signal expandToggled()

    // UI-only state; reset whenever the row collapses or the panel closes.
    property string viewMode: ""
    property bool effectListOpen: false

    readonly property var st: root.ready ? root.nl.stateFor(device.id) : ({ reachable: false, info: null })
    readonly property var info: st.info
    readonly property bool reachable: st.reachable && info !== null
    readonly property bool isOn: reachable && info.on
    readonly property string deviceMode: root.ready && reachable ? root.nl.modeFor(device.id) : "effect"
    readonly property string shownMode: viewMode !== "" ? viewMode : deviceMode
    readonly property var effects: root.ready && reachable ? root.nl.effectsFor(device.id) : []

    readonly property string modeLabel: {
      if (!reachable) return ""
      if (deviceMode === "effect") return info.effect
      if (deviceMode === "white") return info.ct + " K"
      return root.tr("color")
    }
    readonly property string subtitle: {
      if (!reachable) return root.tr("unreachable")
      if (!isOn) return root.tr("off")
      return info.brightness + " %" + (modeLabel !== "" ? " · " + modeLabel : "")
    }

    function resetView() {
      viewMode = ""
      effectListOpen = false
    }

    onExpandedChanged: if (!expanded) resetView()

    Connections {
      target: root
      function onOpenedChanged() { dRow.resetView() }
    }

    width: column.width
    spacing: Style.space(10)

    // ---------- Collapsed row ----------
    Item {
      width: parent.width
      implicitHeight: Math.max(nameCol.implicitHeight, rowSwitch.implicitHeight)
      opacity: dRow.reachable ? 1 : 0.45

      MouseArea {
        anchors.fill: parent
        enabled: dRow.reachable && !root.singleDevice
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: dRow.expandToggled()
      }

      Column {
        id: nameCol
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          text: dRow.device.name
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: dRow.subtitle
          color: root.bar.foreground
          opacity: 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Text {
        id: chevron
        visible: !root.singleDevice && dRow.reachable
        textFormat: Text.PlainText
        text: dRow.expanded ? root.iconCollapse : root.iconExpand
        color: root.bar.foreground
        opacity: 0.6
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.right: rowSwitch.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }

      ToggleSwitch {
        id: rowSwitch
        checked: dRow.isOn
        busy: !dRow.reachable
        foreground: root.bar.foreground
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        onToggled: root.nl.toggle(dRow.device.id)
      }
    }

    // ---------- Expanded ----------
    Column {
      visible: dRow.expanded && dRow.reachable
      width: parent.width
      spacing: Style.space(10)

      // Brightness · identify
      Item {
        width: parent.width
        implicitHeight: devBrightness.implicitHeight

        BrightnessRow {
          id: devBrightness
          anchors.left: parent.left
          anchors.right: identifyBtn.left
          anchors.rightMargin: Style.space(6)
          value: dRow.isOn ? dRow.info.brightness : 0
          onCommitted: function(v) { root.nl.setBrightness(dRow.device.id, v) }
        }

        PanelActionButton {
          id: identifyBtn
          iconText: root.iconIdentify
          tooltipText: root.tr("identify")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.nl.identify(dRow.device.id)
        }
      }

      // Mode switch. Switching only changes the view; nothing is sent until
      // a value is picked, so a stray click never ends a running effect.
      ButtonGroup {
        options: [
          { value: "effect", label: root.tr("tabScene") },
          { value: "color", label: root.tr("tabColor") },
          { value: "white", label: root.tr("tabWhite") }
        ]
        value: dRow.shownMode
        focusable: false
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        fontSize: Style.font.bodySmall
        onChanged: function(v) {
          dRow.viewMode = v
          dRow.effectListOpen = false
        }
      }

      // ---------- Scene ----------
      Column {
        visible: dRow.shownMode === "effect"
        width: parent.width
        spacing: Style.space(4)

        Button {
          width: parent.width
          text: (dRow.deviceMode === "effect" && dRow.info ? dRow.info.effect : root.tr("chooseScene"))
                + "  " + (dRow.effectListOpen ? root.iconCollapse : root.iconExpand)
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          enabled: dRow.effects.length > 0
          onClicked: dRow.effectListOpen = !dRow.effectListOpen
        }

        HintText {
          visible: dRow.effects.length === 0
          text: root.tr("noScenes")
        }

        // Inline list instead of a dropdown popup: popups are clipped to the
        // panel window.
        ListView {
          id: effectList
          visible: dRow.effectListOpen
          width: parent.width
          height: Math.min(contentHeight, Style.space(28) * 6)
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          model: dRow.effectListOpen ? dRow.effects : []

          delegate: Rectangle {
            required property var modelData
            readonly property bool current: dRow.deviceMode === "effect" && dRow.info && dRow.info.effect === modelData
            width: effectList.width
            height: Style.space(28)
            radius: Style.cornerRadius
            color: effectMouse.containsMouse
              ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
              : "transparent"

            Text {
              textFormat: Text.PlainText
              text: modelData
              color: parent.current ? Color.accent : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: parent.current
              elide: Text.ElideRight
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
            }

            MouseArea {
              id: effectMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.nl.selectEffect(dRow.device.id, modelData)
                dRow.viewMode = ""
                dRow.effectListOpen = false
              }
            }
          }
        }
      }

      // ---------- Color ----------
      Column {
        visible: dRow.shownMode === "color"
        width: parent.width
        spacing: Style.space(10)

        // Swatches spread over the full width.
        Row {
          id: swatchRow
          width: parent.width
          readonly property real swatch: Style.space(22)
          spacing: root.colorPresets.length > 1
            ? Math.max(Style.space(4), (width - swatch * root.colorPresets.length) / (root.colorPresets.length - 1))
            : 0

          Repeater {
            model: root.colorPresets
            Rectangle {
              required property var modelData
              readonly property bool current: dRow.deviceMode === "color" && dRow.info
                && Math.abs(dRow.info.hue - modelData.h) <= 3 && Math.abs(dRow.info.sat - modelData.s) <= 3
              width: swatchRow.swatch
              height: swatchRow.swatch
              radius: width / 2
              color: Qt.hsva(modelData.h / 360, modelData.s / 100, 1, 1)
              border.width: current ? Math.max(2, Style.space(3)) : 0
              border.color: root.bar.foreground

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.nl.setColor(dRow.device.id, modelData.h, modelData.s)
                  dRow.viewMode = ""
                }
              }
            }
          }
        }

        // Free color: hue + saturation. Outside color mode (effect running,
        // or a temperature set) the sliders start at full saturation so a
        // hue pick never comes out white.
        Column {
          width: parent.width
          spacing: Style.space(6)

          readonly property bool inColor: dRow.deviceMode === "color" && dRow.info !== null
          readonly property real currentSat: inColor ? dRow.info.sat : 100
          // The slider runs from full color (left) to white (right).
          readonly property real pickedSat: 100 - satSlider.liveValue

          GradientSlider {
            id: hueSlider
            width: parent.width
            minimum: 0
            maximum: 360
            value: parent.inColor ? dRow.info.hue : 0
            stops: ["#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#ff0000"]
            onCommitted: function(v) {
              root.nl.setColor(dRow.device.id, v, parent.pickedSat)
              dRow.viewMode = ""
            }
          }

          GradientSlider {
            id: satSlider
            width: parent.width
            minimum: 0
            maximum: 100
            value: 100 - parent.currentSat
            stops: [Qt.hsva(hueSlider.liveValue / 360, 1, 1, 1), "#ffffff"]
            onCommitted: function(v) {
              root.nl.setColor(dRow.device.id, hueSlider.liveValue, 100 - v)
              dRow.viewMode = ""
            }
          }
        }
      }

      // ---------- Color temperature ----------
      Column {
        visible: dRow.shownMode === "white"
        width: parent.width
        spacing: Style.space(4)

        GradientSlider {
          id: ctSlider
          width: parent.width
          minimum: dRow.info ? Math.max(dRow.info.ctMin, 2000) : 2000
          maximum: dRow.info ? dRow.info.ctMax : 6500
          value: dRow.info && dRow.deviceMode === "white" ? dRow.info.ct : 2700
          stops: ["#ff9b3d", "#ffd3a6", "#fff6ed", "#dfe9ff"]
          onCommitted: function(v) {
            root.nl.setWhite(dRow.device.id, Math.round(v / 100) * 100)
            dRow.viewMode = ""
          }
        }

        Item {
          width: parent.width
          implicitHeight: ctValue.implicitHeight

          HintText { text: root.tr("warm"); width: implicitWidth; anchors.left: parent.left }
          HintText {
            id: ctValue
            text: Math.round(ctSlider.liveValue / 100) * 100 + " K"
            width: implicitWidth
            opacity: 1
            anchors.horizontalCenter: parent.horizontalCenter
          }
          HintText { text: root.tr("cool"); width: implicitWidth; anchors.right: parent.right }
        }
      }
    }
  }
}
