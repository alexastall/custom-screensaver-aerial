/*
 * Aerial screensaver.
 *
 * Usage:
 *   mount --bind ./screensaver-main.qml /usr/palm/applications/com.webos.app.screensaver/qml/main.qml
 *
 * Test launch (prefer system path — do not applicationManager/launch as a card):
 *   luna-send -n 1 'luna://com.webos.service.tvpower/power/turnOnScreenSaver' '{}'
 *
 * Display notes (webOS 4.x / 65UM7400PLB):
 *  - libItems PunchThrough exists but logs "setWindowPunchThroughRectFunc is not
 *    defined" — the compositor never registers the hook, so PunchThrough is a no-op.
 *  - umedia (libqtmultimedia_umedia.so) always renders to a HW video plane, not
 *    into the QML framebuffer. Video { opacity: 1 } does not paint pixels.
 *  - Mitigation when punch-through is broken: transparent WebOSWindow + Video at
 *    opacity 0 so the plane can show under the UI layer. No black fade overlay.
 *  - Launch ONLY via tvpower turnOnScreenSaver (not applicationManager/launch).
 *    App-launch leaves Home chrome visible through the transparent window and
 *    can stick remote input until qml-runner is killed.
 *  - Keep _WEBOS_WINDOW_TYPE_SCREENSAVER for power/idle. Avoid CARD.
 *  - Close Netflix / AirPlay / Live TV / HDMI before testing; they steal the plane.
 *  - settings.forceLocalTest plays assets/test-local.mp4 via file:// (A/B codec/net).
 */
import QtQuick 2.4
import QtMultimedia 5.6
import Eos.Window 0.1
import Eos.Items 0.1
import WebOS.Global 1.0
import QtQuick.Window 2.2
import WebOSServices 1.0
import iLib 1.0 as I

WebOSWindow {
    id : window
    width : 1920
    height : 1080
    windowType : "_WEBOS_WINDOW_TYPE_SCREENSAVER"
    // Transparent so HW plane can show when punch-through is a no-op.
    // Home chrome must be hidden by system screensaver mode (turnOnScreenSaver),
    // not by painting opaque black (that covers the video plane on webOS 4).
    color : "transparent"
    appId : "com.webos.app.screensaver"
    visible : true
    property var poi
    property var poiIndex: 0
    property var settings
    property var playList
    property int randomIndex
    property int stalledCounter : 0
    property string sourceAlt
    property bool resourcesReady : false
    property string activeSource : ""
    property string punchNote : "init"
    property string basePath : "file:///media/developer/apps/usr/palm/applications/org.aabytt.webos.custom-screensaver-aerial/assets/"
    property string localTestUrl : basePath + "test-local.mp4"

    Component.onCompleted : {
        init()
        notificationsService.set('disable')
        Qt.callLater(function () {
            applyPunchThrough()
            // WebOSWindow has no focus property; use keyCatcher Item
            keyCatcher.forceActiveFocus()
        })
    }

    Component.onDestruction : {
        try {
            videoOutput.stop()
            videoOutput.source = ""
        } catch (e) {}
        notificationsService.set('enable')
    }

    // Key sink (WebOSWindow itself cannot take focus on this platform)
    Item {
        id : keyCatcher
        anchors.fill : parent
        focus : true
        Keys.onPressed : {
            try {
                videoOutput.stop()
                videoOutput.source = ""
            } catch (e) {}
            notificationsService.set('enable')
            dismissService.dismiss()
            event.accepted = true
        }
    }

    I.ILib {
        id : ilib
    }
    FontLoader {
        id : segoeUILight
        source : basePath + 'SegoeUI-Light.ttf'
    }
    Timer {
        id : refreshOSD
        interval : 1000
        running : true
        repeat : true
        onTriggered : {
            if (!resourcesReady)
                return
            checkError()
            checkStatus()
            updateOSD()
        }
    }

    // Best-effort; on this webOS 4 Lite build the platform never sets
    // setWindowPunchThroughRectFunc, so this is typically a no-op.
    PunchThrough {
        id : punchThroughArea
        x : 0
        y : 0
        z : -1
        width : parent.width
        height : parent.height
        visible : true
        Component.onCompleted : {
            applyPunchThrough()
        }
        onWidthChanged : applyPunchThrough()
        onHeightChanged : applyPunchThrough()
    }

    Video {
        id : videoOutput
        // HW-plane output: do not paint an opaque QML frame over it
        fillMode : VideoOutput.PreserveAspectCrop
        // Full window — short height left home dock visible under transparent UI
        width : parent.width
        height : parent.height
        x : 0
        y : 0
        z : 0
        opacity : 0
        source : ""
        visible : true
        autoPlay : true
        onStopped : {
            osd.visible = false
        }
        onPaused : {
            // Do not auto-advance on pause — remote/system pause must dismiss cleanly
            osd.visible = false
        }
        onPlaying : {
            applyPunchThrough()
            fadeInOsd.running = true
            osd.visible = true
            stalledCounter = 0
            keyCatcher.forceActiveFocus()
        }
    }

    // Marker that QML graphics plane is alive (green bar top-left)
    Rectangle {
        id : planeMarker
        z : 4
        width : 48
        height : 12
        x : 24
        y : 24
        color : "#00ff66"
        opacity : 0.9
        visible : settings && settings.debug
    }

    Rectangle {
        id : osd
        opacity : 0
        visible : true
        color : "transparent"
        z : 2
        anchors.fill : parent
        anchors.margins : 65
        OpacityAnimator {
            id : fadeInOsd
            target : osd
            from : 0
            to : 1
            duration : 3000
            running : false
        }
        OpacityAnimator {
            id : fadeOutOsd
            target : osd
            from : 1
            to : 0
            duration : 5000
            running : false
        }
        Text {
            id : name
            opacity : (settings && settings.osdOpacity !== undefined) ? settings.osdOpacity / 100 : 0.6
            text : (resourcesReady && poi && playList) ? (poi.strings[playList.assets[randomIndex].localizedNameKey] || "") : ""
            font.family : segoeUILight.name
            font.letterSpacing : -1
            fontSizeMode : Text.Fit
            font.pixelSize : 56
            y : parent.height * 0.9
            color : "white"
            style : Text.Raised
            styleColor : "black"
        }
        Text {
            id : poiOSD
            opacity : name.opacity
            text : (resourcesReady && poi && playList) ? (poi.strings[playList.assets[randomIndex].pointsOfInterest[poiIndex]] || "") : ""
            font.family : name.font.family
            font.letterSpacing : name.font.letterSpacing
            fontSizeMode : name.fontSizeMode
            font.pixelSize : name.font.pixelSize - 16
            y : name.y + name.font.pixelSize + 10
            color : name.color
            style : name.style
            styleColor : name.styleColor
        }
        Text {
            id : timeOSD
            horizontalAlignment : Text.AlignRight
            anchors.right : parent.right
            opacity : name.opacity
            font.family : name.font.family
            font.letterSpacing : name.font.letterSpacing
            font.pixelSize : name.font.pixelSize + 23
            y : dateOSD.y - name.font.pixelSize - 40
            color : name.color
            style : name.style
            styleColor : name.styleColor
            fontSizeMode : name.fontSizeMode
        }
        Text {
            id : dateOSD
            horizontalAlignment : Text.AlignRight
            anchors.right : parent.right
            opacity : name.opacity
            font.family : name.font.family
            font.letterSpacing : name.font.letterSpacing
            font.pixelSize : name.font.pixelSize - 16
            y : name.y + name.font.pixelSize + 5
            color : name.color
            style : name.style
            styleColor : name.styleColor
            fontSizeMode : name.fontSizeMode
        }
    }
    Text {
        id : debug
        z : 3
        visible : settings && settings.debug
        horizontalAlignment : Text.AlignRight
        anchors.right : parent.right
        anchors.margins : 25
        opacity : 0.85
        font.family : name.font.family
        font.pixelSize : name.font.pixelSize - 30
        color : "white"
        style : Text.Raised
        styleColor : "black"
        fontSizeMode : name.fontSizeMode
    }

    function applyPunchThrough() {
        try {
            if (typeof punchThroughArea.setRegion === "function") {
                punchThroughArea.setRegion(Qt.rect(0, 0, punchThroughArea.width, punchThroughArea.height))
                punchNote = "setRegion ok " + Math.floor(punchThroughArea.width) + "x" + Math.floor(punchThroughArea.height)
            } else {
                punchNote = "no setRegion"
            }
            punchThroughArea.visible = true
        } catch (e) {
            punchNote = "setRegion err: " + e
        }
    }

    function init() {
        loadJSONData(basePath + 'settings.json', 'settings', loadResources)
    }
    function loadResources() {
        loadJSONData(basePath + 'videos.json', 'playList', function () {
            loadJSONData(basePath + 'locales/' + settings.localeLang + '.json', 'poi', function () {
                resourcesReady = true
                playRandomVideo()
            })
        })
    }
    function pickSource(asset) {
        if (settings && settings.forceLocalTest) {
            sourceAlt = " - LOCAL test-local.mp4"
            return localTestUrl
        }
        var preferred = settings.sourceType
        if (asset[preferred]) {
            sourceAlt = ""
            return asset[preferred]
        }
        if (!settings.playLowerQuality)
            return ""

        var fallbacks = []
        if (preferred.indexOf("4K") >= 0 || preferred.indexOf("HDR") >= 0) {
            fallbacks = ["url-4K-SDR", "url-1080-SDR", "url-1080-H264"]
        } else if (preferred === "url-1080-SDR") {
            fallbacks = ["url-1080-H264"]
        } else if (preferred === "url-1080-HDR") {
            fallbacks = ["url-1080-SDR", "url-1080-H264"]
        }

        for (var i = 0; i < fallbacks.length; i++) {
            if (fallbacks[i] !== preferred && asset[fallbacks[i]]) {
                sourceAlt = " - n/a, trying " + fallbacks[i]
                return asset[fallbacks[i]]
            }
        }
        return ""
    }
    function playRandomVideo() {
        if (!playList || !playList.assets || !playList.assets.length || !settings)
            return
        stalledCounter = 0

        if (settings.forceLocalTest) {
            randomIndex = 0
            notificationsService.set('disable')
            activeSource = localTestUrl
            sourceAlt = " - LOCAL test-local.mp4"
            videoOutput.source = localTestUrl
            videoOutput.play()
            applyPunchThrough()
            return
        }

        var attempts = 0
        var maxAttempts = playList.assets.length + 2
        while (attempts < maxAttempts) {
            attempts++
            randomIndex = Math.floor(Math.random() * playList.assets.length)
            var asset = playList.assets[randomIndex]
            if (asset.viewed)
                continue
            var url = pickSource(asset)
            if (url) {
                notificationsService.set('disable')
                activeSource = url
                videoOutput.source = url
                videoOutput.play()
                applyPunchThrough()
                return
            }
        }
        for (var j = 0; j < playList.assets.length; j++)
            playList.assets[j].viewed = false
        randomIndex = Math.floor(Math.random() * playList.assets.length)
        var retryUrl = pickSource(playList.assets[randomIndex])
        if (retryUrl) {
            activeSource = retryUrl
            videoOutput.source = retryUrl
            videoOutput.play()
            applyPunchThrough()
        }
    }

    function checkError() {
        if (videoOutput.error !== 0) {
            notificationsService.set('enable')
            // Do not tight-loop local test on error
            if (settings && settings.forceLocalTest)
                return
            playRandomVideo()
        }
    }

    function checkStatus() {
        if (!playList || !settings)
            return
        if (videoOutput.position > 2000) {
            notificationsService.set('enable')
            if (!settings.forceLocalTest)
                playList.assets[randomIndex].viewed = true
        }
        if (videoOutput.duration > 0 && Math.floor(videoOutput.position / 1000) == Math.floor(videoOutput.duration / 1000) - 5) {
            fadeOutOsd.running = true
        }
        if (videoOutput.status == MediaPlayer.EndOfMedia) {
            if (settings.forceLocalTest) {
                // Loop local test clip
                videoOutput.seek(0)
                videoOutput.play()
            } else {
                playRandomVideo()
            }
        }
        if (videoOutput.status === 1)
            var status = 'NoMedia'
        else if (videoOutput.status === 2) {
            var status = 'Loading'
            stalledCounter ++
            if (stalledCounter > 25 && !settings.forceLocalTest) {
                playRandomVideo()
            }
        }
        else if (videoOutput.status === 3)
            var status = 'Loaded'
        else if (videoOutput.status === 4)
            var status = 'Buffering'
        else if (videoOutput.status === 5) {
            var status = 'Stalled'
            stalledCounter ++
            if (stalledCounter > 25 && !settings.forceLocalTest) {
                playRandomVideo()
            }
        }
        else if (videoOutput.status === 6)
            var status = 'Buffered'
         else if (videoOutput.status === 7)
            var status = 'EndOfMedia'
         else if (videoOutput.status === 8)
            var status = 'InvalidMedia'
         else if (videoOutput.status === 0)
            var status = 'UnknownStatus'

        if (videoOutput.playbackState === 1)
            var playbackState = 'playing'
         else if (videoOutput.playbackState === 2)
            var playbackState = 'paused'
         else if (videoOutput.playbackState === 0){
            var playbackState = 'stopped'
            stalledCounter ++
            if (stalledCounter > 15 && !settings.forceLocalTest) {
                playRandomVideo()
            }
        }

        var srcShort = activeSource
        if (srcShort.length > 60)
            srcShort = srcShort.substring(0, 28) + "..." + srcShort.substring(srcShort.length - 28)

        debug.text = "Video " + randomIndex + " of " + playList.assets.length +
        "\n Source Type: " + settings.sourceType + sourceAlt +
        "\n ForceLocal: " + !!settings.forceLocalTest +
        "\n Window: " + window.windowType + " color=transparent" +
        "\n Punch: " + punchThroughArea.visible + " | " + punchNote +
        "\n Source: " + srcShort +
        "\n Try Other Source: " + settings.playLowerQuality +
        "\n Locale: " + settings.localeLang +
        "\n OSD opacity: " + settings.osdOpacity + "%" +
        "\n Timecode: " + Math.floor(videoOutput.position / 1000) + " / " + Math.floor(videoOutput.duration / 1000) +
        "\n Media Status: " + status +
        "\n Stalled Timeout: " + (25 - stalledCounter) +
        "\n Error: " + videoOutput.error + " " + videoOutput.errorString +
        "\n Playback State: " + playbackState +
        "\n Buffer Progress : " + (
        videoOutput.bufferProgress * 33.334).toFixed(0) + "%"
    }
    function updateOSD() {
        if (!settings || !poi || !playList)
            return
        var DateFmt = ilib.require("DateFmt.js")
        var now = new Date()
        var time = new DateFmt({
            locale: settings.localeLang,
            timezone: "local",
            type: "time",
            length: "full"
        })
        var day = new DateFmt({
            locale: settings.localeLang,
            timezone: "local",
            type: "date",
            date: "dmw",
            length: "full"
        })
        timeOSD.text = time.format(now)
        if (poi.date)
            dateOSD.text = poi.date.daysOfWeek[now.getDay()
            ] + ", " + now.getDate() + " " + poi.date.months[now.getMonth()
            ]
         else
            dateOSD.text = day.format(now)

        if (playList.assets[randomIndex] && playList.assets[randomIndex].pointsOfInterest &&
            playList.assets[randomIndex].pointsOfInterest[Math.floor(videoOutput.position / 1000)])
            poiIndex = Math.floor(videoOutput.position / 1000)
    }

    Service {
        id : notificationsService
        // Hard-coded: globalVars is missing in some qml-runner contexts (webOS 4)
        appId : "com.webos.app.screensaver"
        function set(param) {
            call("luna://com.webos.notification/", param)
        }
    }
    Service {
        id : dismissService
        appId : "com.webos.app.screensaver"
        function dismiss() {
            // Best-effort cleanup so remote works after a key press
            call("luna://com.webos.service.tvpower/power/turnOffScreenSaver", "{}")
            call("luna://com.webos.applicationManager/closeByAppId",
                 '{"id":"com.webos.app.screensaver"}')
        }
    }
    function loadJSONData(url, targetVar, callback) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var jsonData = JSON.parse(xhr.responseText)
                    eval(targetVar + " = jsonData")
                    if (typeof callback === "function")
                        callback()
                } else {
                    console.error("Error loading JSON data:", xhr.statusText)
                    name.text = xhr.statusText
                }
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }
}
