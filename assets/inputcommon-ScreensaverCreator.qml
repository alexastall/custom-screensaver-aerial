import QtQuick 2.6
import "../View"
import "../Model/ScreensaverViewModel.js" as ViewModel
import WebOSServices 1.0

/*
 * Aerial replacement for Live TV / HDMI stock screensaver.
 *
 * Bind-mounted over:
 *   /usr/palm/applications/com.webos.app.inputcommon/qml/InvisibleComponent/ScreensaverCreator.qml
 *
 * When the tuner/HDMI would show "Not Programmed", "No Signal", etc., start the
 * system Aerial screensaver (com.webos.app.screensaver — our bind-mounted QML)
 * instead of LG photo slides. Never create the stock Screensaver/PhotoPlayer UI.
 *
 * Requires apply.sh aerial QML bind + this creator bind. Restart Live TV /
 * inputcommon after apply so the patched QML is loaded.
 */
TvComponentBase {
    componentId: "screensaverCreator"

    property var    screensaver         : null
    property var    photoPlayer         : null
    property var    screensaverModel    : modelManager.getModel("screensaverModel")
    property var    noSignalPhotoModel  : (globalVars.isSupportPhotoPlayer)
                                          ? modelManager.getModel("noSignalExPhotoModel")
                                          : modelManager.getModel("noSignalPhotoModel")
    property string currentScreensaver  : screensaverModel ? screensaverModel.currentScreensaver : ""
    property bool   isOtherScreensaver  : screensaverModel ? screensaverModel.isOtherScreensaver : false
    property bool   aerialLaunched      : false

    function wantsAerial(type) {
        if (!type || type === "")
            return false
        // Explicit no-op / good-signal states
        if (type === ViewModel.messageType.noScreensaver)
            return false
        if (type === "NO_SCREEN_SAVER" || type === "UNKNOWN")
            return false

        // Primary cases users see on unused antenna / empty channel / dead HDMI
        if (type === ViewModel.messageType.notProgrammed
                || type === ViewModel.messageType.noSignal
                || type === ViewModel.messageType.invalidService
                || type === ViewModel.messageType.noCIModule
                || type === ViewModel.messageType.invalidFormat
                || type === ViewModel.messageType.audioOnly
                || type === ViewModel.messageType.dataOnly
                || type === ViewModel.messageType.notSupported
                || type === ViewModel.messageType.serverUnavailable
                || type === ViewModel.messageType.noNetwork)
            return true

        // Raw strings if model ever bypasses ViewModel keys
        if (type === "NOT_PROGRAMMED" || type === "NO_SIGNAL"
                || type === "INVALID_SERVICE" || type === "NO_CI_MODULE")
            return true

        return false
    }

    Service {
        id: turnOnScreenSaverSvc
        appId: globalVars.appId
        service: "com.webos.service.tvpower/power"
        method: "turnOnScreenSaver"
        onResponse: {
            console.log("[AerialCreator] turnOnScreenSaver: " + payload)
        }
    }

    Service {
        id: launchScreensaverSvc
        appId: globalVars.appId
        service: "com.webos.applicationManager"
        method: "launch"
        onResponse: {
            console.log("[AerialCreator] launch screensaver: " + payload)
        }
    }

    Service {
        id: closeScreensaverSvc
        appId: globalVars.appId
        service: "com.webos.applicationManager"
        method: "closeByAppId"
        onResponse: {
            console.log("[AerialCreator] close screensaver: " + payload)
        }
    }

    // Debounce rapid signal flaps (common on no-signal tuner)
    Timer {
        id: startDebounce
        interval: 600
        repeat: false
        onTriggered: doStartAerial()
    }

    // turnOnScreenSaver often no-ops while Live TV is foreground; launch is reliable
    Timer {
        id: launchFallback
        interval: 1200
        repeat: false
        onTriggered: {
            if (aerialLaunched && wantsAerial(currentScreensaver)) {
                console.log("[AerialCreator] launch fallback com.webos.app.screensaver")
                launchScreensaverSvc.callService({ "id": "com.webos.app.screensaver" })
            }
        }
    }

    function doStartAerial() {
        if (!wantsAerial(currentScreensaver))
            return
        console.log("[AerialCreator] start Aerial for type=" + currentScreensaver)
        aerialLaunched = true
        turnOnScreenSaverSvc.callService({})
        launchFallback.restart()
    }

    function startAerial() {
        startDebounce.restart()
    }

    function stopAerial() {
        startDebounce.stop()
        launchFallback.stop()
        if (!aerialLaunched)
            return
        console.log("[AerialCreator] stop Aerial")
        aerialLaunched = false
        closeScreensaverSvc.callService({ "id": "com.webos.app.screensaver" })
    }

    // Stock API — never create photo UI (that was the override problem)
    function setScreensaverComponent() {
    }

    function isNeedScreensaver() {
        return false
    }

    onCurrentScreensaverChanged: {
        console.log("[AerialCreator] currentScreensaver=" + currentScreensaver)
        if (wantsAerial(currentScreensaver))
            startAerial()
        else
            stopAerial()
    }

    onIsOtherScreensaverChanged: {
        // System idle aerial already active — leave it; never create stock UI
        console.log("[AerialCreator] isOtherScreensaver=" + isOtherScreensaver)
    }

    Component.onDestruction: {
        stopAerial()
    }
}
