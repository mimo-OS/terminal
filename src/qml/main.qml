/*
 * Copyright (C) 2021 CutefishOS Team.
 *
 * Author:     Reion Wong <reionwong@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick

import Cutefish.TermWidget
import FishUI 1.0 as FishUI

FishUI.Window {
    id: root
    minimumWidth: 400
    minimumHeight: 300
    width: settings.width
    height: settings.height
    title: currentItem ? currentItem.title : ""

    property bool blurEnabled: settings.blur
    background.color: terminalBackground
    background.opacity: settings.blur ? settings.opacity : 1.0
    background.border.color: root.chromeDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.10)
    property bool headerDarkMode: chromeDark
    header.height: 44
    windowButtonsAlignment: Qt.AlignVCenter
    windowButtonsTopMargin: 0
    windowButtonsRightMargin: FishUI.Units.smallSpacing

    property int currentIndex: -1
    property alias currentItem: _tabView.currentItem
    readonly property int tabCount: _tabView.count
    readonly property QMLTermWidget currentTerminal: currentItem ? currentItem.terminal : null

    // Zoom is for this window only; the size in Settings stays the default.
    property int fontZoom: 0
    readonly property int fontPointSize: Math.max(5, Math.min(40, settings.fontPointSize + fontZoom))

    function zoom(step) {
        const size = step === 0 ? settings.fontPointSize : fontPointSize + step
        fontZoom = Math.max(5, Math.min(40, size)) - settings.fontPointSize
        _zoomIndicator.show()
    }

    function isThemeLight(name) {
        return ["TokyoNight-Day", "One-Light", "Catppuccin-Latte", "Gruvbox-Light", "SolarizedLight"].indexOf(name) !== -1
    }

    // Determine if we should render light mode:
    // 0 = Follow System (matches !FishUI.Theme.darkMode)
    // 1 = Light
    // 2 = Dark
    readonly property bool isLightMode: {
        if (settings.themeMode === 1) return true
        if (settings.themeMode === 2) return false
        return !FishUI.Theme.darkMode
    }

    readonly property string effectiveLightScheme: {
        if (settings.colorSchemeLight !== "") return settings.colorSchemeLight
        if (isThemeLight(settings.colorScheme)) return settings.colorScheme
        return "TokyoNight-Day"
    }

    readonly property string effectiveDarkScheme: {
        if (settings.colorSchemeDark !== "") return settings.colorSchemeDark
        if (!isThemeLight(settings.colorScheme) && settings.colorScheme !== "") return settings.colorScheme
        return "TokyoNight"
    }

    readonly property string colorScheme: isLightMode ? effectiveLightScheme : effectiveDarkScheme
    readonly property var colorSchemeInfo: currentTerminal ? currentTerminal.colorSchemeInfo(colorScheme) : ({})

    // The scheme's own background, so cells in the default colour and the
    // window around the text are one surface.
    readonly property color terminalBackground: colorSchemeInfo.background
                                                ? colorSchemeInfo.background
                                                : (chromeDark ? "#1A1B26" : "#E1E2E7")

    // The title bar is painted with the terminal, so its text and buttons follow
    // the scheme rather than the system theme.
    readonly property color chromeForeground: colorSchemeInfo.foreground ? colorSchemeInfo.foreground
                                                                         : (chromeDark ? "#C0CAF5" : "#3760BF")
    readonly property bool chromeDark: 0.2126 * terminalBackground.r + 0.7152 * terminalBackground.g
                                       + 0.0722 * terminalBackground.b < 0.5

    GlobalSettings { id: settings }

    // Each dialog is a window of its own, so it is made the first time it is needed.
    property QtObject _exitPrompt: null
    property QtObject _settingsDialog: null
    property QtObject _pasteConfirm: null

    // Asks before running action when a process is still running in one of pages.
    function confirmClose(pages, action) {
        if (!pages.some(page => page.session.hasActiveProcess)) {
            action()
            return
        }

        if (!_exitPrompt)
            _exitPrompt = _exitPromptComponent.createObject(root)
        _exitPrompt.pendingAction = action
        _exitPrompt.open()
    }

    function showSettings() {
        if (!_settingsDialog)
            _settingsDialog = _settingsDialogComponent.createObject(root)
        _settingsDialog.show()
        _settingsDialog.raise()
    }

    Component {
        id: _exitPromptComponent

        ExitPromptDialog {
            x: root.x + Math.round((root.width - width) / 2)
            y: root.y + Math.round((root.height - height) / 2)
        }
    }

    Component {
        id: _settingsDialogComponent

        SettingsDialog {
        }
    }

    // Line breaks in a paste run as if Enter were pressed, so a paste with any
    // waits here first.
    Component {
        id: _pasteConfirmComponent

        FishUI.ConfirmDialog {
            property var pendingAction: null
            property int lineCount: 0

            x: root.x + Math.round((root.width - width) / 2)
            y: root.y + Math.round((root.height - height) / 2)
            title: lineCount > 1 ? qsTr("Paste %1 lines?").arg(lineCount) : qsTr("Paste this line and press Enter?")
            confirmText: qsTr("Paste")

            onAccepted: {
                if (pendingAction)
                    pendingAction()
                pendingAction = null
            }
            onRejected: pendingAction = null
        }
    }

    function confirmPaste(text, action) {
        const lines = text.replace(/\n+$/, "").split("\n")
        const shown = lines.slice(0, 4).map(line => line.length > 60 ? line.substring(0, 59) + "…" : line)
        if (lines.length > 4)
            shown.push("…")

        if (!_pasteConfirm)
            _pasteConfirm = _pasteConfirmComponent.createObject(root)

        _pasteConfirm.lineCount = lines.length
        _pasteConfirm.text = shown.join("\n")
        _pasteConfirm.pendingAction = action
        _pasteConfirm.open()
    }

    onClosing: (close) => {
        if (!root.isMaximized && !root.isFullScreen) {
            settings.width = root.width
            settings.height = root.height
        }

        if (_quitting)
            return

        const pages = tabs()
        if (pages.some(page => page.session.hasActiveProcess)) {
            close.accepted = false
            confirmClose(pages, () => {
                _quitting = true
                root.close()
            })
        }
    }

    headerItem: Item {
        id: _header

        // Width taken by the window buttons, mirrored on the left so the
        // title is centred on the window rather than on this item.
        readonly property real reservedWidth: root.width - width + _newTabButton.width

        FishUI.Label {
            visible: _tabView.count < 2
            width: Math.min(implicitWidth, root.width - _header.reservedWidth * 2)
            x: (root.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            elide: Text.ElideMiddle
            font.family: settings.fontName
            font.pixelSize: 13
            font.weight: Font.Medium
            color: root.active ? root.chromeForeground
                               : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.5)
        }

        TabBar {
            id: _tabBar
            visible: _tabView.count > 1
            view: _tabView
            darkMode: root.chromeDark
            textColor: root.chromeForeground
            anchors.left: parent.left
            anchors.right: _newTabButton.left
            anchors.leftMargin: FishUI.Units.largeSpacing
            anchors.rightMargin: FishUI.Units.smallSpacing
            anchors.verticalCenter: parent.verticalCenter

            onCloseRequested: (index) => root.closeProtection(index)
            onCloseOthersRequested: (index) => root.closeOtherTabs(index)
            onMoveRequested: (from, to) => root.moveTab(from, to)
            onRenameRequested: (index, title) => {
                _tabView.contentModel.get(index).customTitle = title.trim()
                _tabView.currentItem.forceActiveFocus()
            }
        }

        FishUI.RoundImageButton {
            id: _newTabButton
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            size: 28
            source: "qrc:/fishui/kit/images/" + (root.chromeDark ? "dark/" : "light/") + "add.svg"
            hoveredColor: root.chromeDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
            pressedColor: root.chromeDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15)
            onClicked: root.openNewTab()
        }
    }

    FishUI.TabView {
        id: _tabView
        anchors.fill: parent
    }

    // Shows the size briefly while zooming.
    Rectangle {
        id: _zoomIndicator
        anchors.centerIn: parent
        width: _zoomLabel.implicitWidth + FishUI.Units.largeSpacing * 2
        height: 36
        radius: height / 2
        color: root.chromeDark ? Qt.rgba(0.18, 0.18, 0.22, 0.90) : Qt.rgba(1, 1, 1, 0.92)
        border.width: 1
        border.color: root.chromeDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
        opacity: 0
        visible: opacity > 0

        function show() {
            _zoomFade.stop()
            opacity = 1
            _zoomHide.restart()
        }

        FishUI.Label {
            id: _zoomLabel
            anchors.centerIn: parent
            text: qsTr("%1 pt").arg(root.fontPointSize)
            font.pixelSize: 13
            font.weight: Font.Medium
            color: root.chromeForeground
        }

        Timer {
            id: _zoomHide
            interval: 900
            onTriggered: _zoomFade.start()
        }

        NumberAnimation {
            id: _zoomFade
            target: _zoomIndicator
            property: "opacity"
            to: 0
            duration: 200
        }
    }

    // The visual bell: the whole window, title bar included, briefly lightens,
    // or darkens on a light scheme.
    function flashBell() {
        _bellFade.restart()
    }

    Rectangle {
        id: _bellFlash
        parent: root.contentItem
        anchors.fill: parent
        z: 1000
        color: root.chromeForeground
        opacity: 0
        visible: opacity > 0

        SequentialAnimation {
            id: _bellFade
            PropertyAction { target: _bellFlash; property: "opacity"; value: 0.12 }
            NumberAnimation { target: _bellFlash; property: "opacity"; to: 0; duration: 180 }
        }
    }

    // Set once the close has been confirmed, so closing does not ask again.
    property bool _quitting: false

    Component.onCompleted: {
        // Given on the command line: cutefish-terminal --workdir <dir> -e <command>.
        const directory = typeof StartupDirectory === "string" && StartupDirectory !== "" ? StartupDirectory : "$PWD"
        const command = typeof StartupCommand === "object" ? StartupCommand : []
        openTab(directory, command)
    }

    function openNewTab() {
        if (_tabView.currentItem) {
            openTab(_tabView.currentItem.session.currentDir)
        } else {
            openTab("$HOME")
        }
    }

    property Component _terminalComponent: null

    function openTab(path, command) {
        if (!_terminalComponent)
            _terminalComponent = Qt.createComponent("Terminal.qml")

        if (_terminalComponent.status === Component.Ready) {
            const object = _tabView.addTab(_terminalComponent, { path: path, command: command || [] })
            // Looked up when the shell exits: closing other tabs shifts the index.
            object.terminalClosed.connect(() => closeTab(indexOfTab(object)))
        }
    }

    function indexOfTab(object) {
        for (var i = 0; i < _tabView.contentModel.count; ++i) {
            if (_tabView.contentModel.get(i) === object)
                return i
        }

        return -1
    }

    function tabs() {
        const pages = []
        for (let i = 0; i < _tabView.contentModel.count; ++i)
            pages.push(_tabView.contentModel.get(i))
        return pages
    }

    function closeProtection(index) {
        const page = _tabView.contentModel.get(index)
        if (page)
            confirmClose([page], () => closeTab(indexOfTab(page)))
    }

    function closeOtherTabs(index) {
        const keep = _tabView.contentModel.get(index)
        const others = tabs().filter(page => page !== keep)
        confirmClose(others, () => {
            for (const page of others)
                closeTab(indexOfTab(page))
            _tabView.currentIndex = indexOfTab(keep)
        })
    }

    function selectTab(index) {
        if (index < 0 || index >= _tabView.count)
            return
        _tabView.currentIndex = index
        _tabView.currentItem.forceActiveFocus()
    }

    // Moves the current tab by step, keeping it current.
    function moveCurrentTab(step) {
        moveTab(_tabView.currentIndex, _tabView.currentIndex + step)
    }

    function moveTab(from, to) {
        if (from === to || from < 0 || to < 0 || from >= _tabView.count || to >= _tabView.count)
            return
        const page = _tabView.contentModel.get(from)
        _tabView.moveItem(from, to)
        _tabView.currentIndex = indexOfTab(page)
        page.forceActiveFocus()
    }

    function newWindow() {
        Process.newWindow(currentItem ? currentItem.session.currentDir : "")
    }

    function closeTab(index) {
        if (index < 0)
            return

        _tabView.closeTab(index)

        if (_tabView.contentModel.count === 0)
            Qt.quit()
    }

    function closeCurrentTab() {
        closeProtection(_tabView.currentIndex)
    }

    // Next (step 1) or previous (step -1) tab, wrapping around.
    function cycleTab(step) {
        const count = _tabView.count
        if (count > 1)
            selectTab((_tabView.currentIndex + step + count) % count)
    }
}
