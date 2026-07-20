/*
 * Aerial screensaver.
 *
 * Usage:
 *   mount --bind ./screensaver-main.qml /usr/palm/applications/com.webos.app.screensaver/qml/main.qml
 *
 * Test launch (only this path — do not applicationManager/launch as a card):
 *   luna-send -n 1 'luna://com.webos.service.tvpower/power/turnOnScreenSaver' '{}'
 *
 * Display notes (webOS 4.x):
 *  - MUST use _WEBOS_WINDOW_TYPE_SCREENSAVER so tvpower / remote power and
 *    idle lifecycle work. CARD type can leave the TV with a stuck media
 *    pipeline (power button dead, app launches crash until reboot).
 *  - PunchThrough is often a no-op (setWindowPunchThroughRectFunc missing).
 *    On webOS 4 we paint Video at opacity 1 (QML-composited) so frames show
 *    without relying on the hardware plane punch-through path.
 *  - Active HDMI (e.g. Roku) can own the video plane — leave that input when testing.
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
    // Black base; video is drawn in QML (opacity 1) on webOS 4
    color : "black"
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
    // webOS 4: composite Video into the window. webOS 5+ can use opacity 0 + PunchThrough.
    property bool paintVideoInQml : true
    property string basePath : "file:///media/developer/apps/usr/palm/applications/org.aabytt.webos.custom-screensaver-aerial/assets/"

    Component.onCompleted : {
        init()
        notificationsService.set('disable')
    }

    Component.onDestruction : {
        // Release HW decoder / ACB so power and other apps keep working
        try {
            videoOutput.stop()
            videoOutput.source = ""
        } catch (e) {}
        notificationsService.set('enable')
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

    // Best-effort on webOS 5+; often no-op on webOS 4 — hide when painting in QML
    PunchThrough {
        id : punchThroughArea
        x : 0
        y : 0
        z : -1
        width : parent.width
        height : parent.height - 1
        visible : !paintVideoInQml
    }

    Video {
        id : videoOutput
        // webOS 4: opacity 1 so frames composite into the screensaver window.
        // (opacity 0 only works when HW punch-through is active.)
        fillMode : VideoOutput.PreserveAspectCrop
        width : parent.width
        height : parent.height - 1 // non-fullscreen so system does not auto-kill screensaver
        x : 0
        y : 0
        z : 0
        opacity : paintVideoInQml ? 1 : 0
        source : ""
        visible : true
        autoPlay : true
        onStopped : {
            osd.visible = false
        }
        onPaused : {
            // User activity / system pause — pick next clip only if still resourcesReady
            if (resourcesReady)
                playRandomVideo()
            osd.visible = false
        }
        onPlaying : {
            fadeInOsd.running = true
            osd.visible = true
            stalledCounter = 0
        }
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
                videoOutput.source = url
                videoOutput.play()
                return
            }
        }
        for (var j = 0; j < playList.assets.length; j++)
            playList.assets[j].viewed = false
        randomIndex = Math.floor(Math.random() * playList.assets.length)
        var retryUrl = pickSource(playList.assets[randomIndex])
        if (retryUrl) {
            videoOutput.source = retryUrl
            videoOutput.play()
        }
    }

    function checkError() {
        if (videoOutput.error !== 0) {
            notificationsService.set('enable')
            playRandomVideo()
        }
    }

    function checkStatus() {
        if (!playList || !settings)
            return
        if (videoOutput.position > 2000) {
            notificationsService.set('enable')
            playList.assets[randomIndex].viewed = true
        }
        if (videoOutput.duration > 0 && Math.floor(videoOutput.position / 1000) == Math.floor(videoOutput.duration / 1000) - 5) {
            fadeOutOsd.running = true
        }
        if (videoOutput.status == MediaPlayer.EndOfMedia)
            playRandomVideo()
        if (videoOutput.status === 1)
            var status = 'NoMedia'
        else if (videoOutput.status === 2) {
            var status = 'Loading'
            stalledCounter ++
            if (stalledCounter > 25) {
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
            if (stalledCounter > 25) {
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
            if (stalledCounter > 15) {
                playRandomVideo()
            }
        }

        debug.text = "Video " + randomIndex + " of " + playList.assets.length +
        "\n Source Type: " + settings.sourceType + sourceAlt +
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

        if (playList.assets[randomIndex].pointsOfInterest[Math.floor(videoOutput.position / 1000)])
            poiIndex = Math.floor(videoOutput.position / 1000)
    }

    Service {
        id : notificationsService
        appId : "com.webos.app.screensaver"
        function set(param) {
            call("luna://com.webos.notification/", param)
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
