/*
 * Aerial screensaver.
 *
 * Usage:
 *   mount --bind ./screensaver-main.qml /usr/palm/applications/com.webos.app.screensaver/qml/main.qml
 *
 * Test launch (no way to trigger on "No signal" screen)
 *   luna-send -n 1 'luna://com.webos.service.tvpower/power/turnOnScreenSaver' '{}'
 *   # fallback on some webOS builds:
 *   luna-send -n 1 'luna://com.webos.applicationManager/launch' '{"id":"com.webos.app.screensaver"}'
 *
 * Notes for webOS 4.x:
 *  - Prefer url-1080-H264 (Apple AVC) over 4K/HDR HEVC streams
 *  - globalVars may be missing; hardcode screensaver appId for notifications
 *  - Do not call playRandomVideo until settings + playlist + locale are loaded
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
    property string basePath : "file:///media/developer/apps/usr/palm/applications/org.aabytt.webos.custom-screensaver-aerial/assets/"
    Component.onCompleted : {
        init()
        notificationsService.set('disable')
        // Do not playRandomVideo here — playlist/settings load async via XHR
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
    Video {
        id : videoOutput
        fillMode : VideoOutput.PreserveAspectCrop
        width : parent.width
        height : parent.height - 1 // non fullscreen to avoid screensaver automatic disabling
        source : ""
        visible : true
        autoPlay : true
        onStopped : {
            punchThroughArea.visible = false
            osd.visible = false
            fadeOutVideo.running = false
        }
        onPaused : {
            punchThroughArea.visible = false
            playRandomVideo()
            osd.visible = false
            fadeOutVideo.running = false
        }
        onPlaying : {
            punchThroughArea.visible = true
            fadeInVideo.running = true
            fadeInOsd.running = true
            osd.visible = true
        }
        PunchThrough {
            id : punchThroughArea
            visible : false
            x : 0
            y : 0
            z : -1
            width : parent.width
            height : parent.height
            Rectangle {
                id : opacityBox
                width : 1920
                height : 1080
                z : 1
                color : "black"
                OpacityAnimator {
                    id : fadeInVideo
                    target : opacityBox
                    from : 1
                    to : 0
                    duration : 3000
                    running : false
                }
                OpacityAnimator {
                    id : fadeOutVideo
                    target : opacityBox
                    from : 0
                    to : 1
                    duration : 5000
                    running : false
                }
            }
        }
    }
    Rectangle {
        id : osd
        opacity : 0
        visible : true
        color : "transparent"
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
        visible : settings && settings.debug
        horizontalAlignment : Text.AlignRight
        anchors.right : parent.right
        anchors.margins : 25
        opacity : 0.7
        font.family : name.font.family
        font.pixelSize : name.font.pixelSize - 30
        color : name.color
        style : name.style
        styleColor : name.styleColor
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

        // Prefer progressively more compatible fallbacks (important on webOS 4.x)
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
        // Prefer unviewed assets; if all viewed, reset marks
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
        // All marked viewed or missing URLs — clear viewed flags and try once more
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
            punchThroughArea.visible = false
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
            fadeOutVideo.running = true
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
                punchThroughArea.visible = false
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
                punchThroughArea.visible = false
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
                punchThroughArea.visible = false
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
        // globalVars is unavailable on some webOS 4.x qml-runner contexts
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
