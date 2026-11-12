package com.pulseagent.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import kotlin.math.sqrt

class MainActivity : FlutterActivity(), SensorEventListener {
    companion object {
        const val CHANNEL_NAME = "com.pulseagent.app/agent"
        private const val REQ_PERMS = 7701
        private const val REQ_SPEECH = 7702
        var methodChannel: MethodChannel? = null

        fun notifyEmergencyStop(reason: String) {
            methodChannel?.invokeMethod("onEmergencyStop", reason)
        }

        fun notifyScheduledGoal(goal: String) {
            methodChannel?.invokeMethod("onScheduledGoalTriggered", goal)
        }
    }

    private lateinit var systemBridge: SystemActionBridge
    private var sensorManager: SensorManager? = null
    private var lastShakeTime: Long = 0
    private var tts: TextToSpeech? = null
    private var speechRecognizer: SpeechRecognizer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        systemBridge = SystemActionBridge(this)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        tts = TextToSpeech(applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale("ru", "RU")
                tts?.setSpeechRate(1.0f)
            }
        }
        handleIntentGoal(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntentGoal(intent)
    }

    private fun handleIntentGoal(intent: Intent?) {
        val scheduledGoal = intent?.getStringExtra("scheduled_goal")
        if (!scheduledGoal.isNullOrEmpty()) {
            notifyScheduledGoal(scheduledGoal)
            intent.removeExtra("scheduled_goal")
        }
    }

    override fun onResume() {
        super.onResume()
        sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { accel ->
            sensorManager?.registerListener(this, accel, SensorManager.SENSOR_DELAY_UI)
        }
    }

    override fun onPause() {
        super.onPause()
        sensorManager?.unregisterListener(this)
    }

    override fun onDestroy() {
        try {
            speechRecognizer?.destroy()
            speechRecognizer = null
            tts?.stop()
            tts?.shutdown()
            tts = null
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_ACCELEROMETER) return
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val gForce = sqrt((x * x + y * y + z * z).toDouble()) / SensorManager.GRAVITY_EARTH
        if (gForce > 2.7) {
            val now = System.currentTimeMillis()
            if (now - lastShakeTime > 1500) {
                lastShakeTime = now
                notifyEmergencyStop("Обнаружено встряхивание телефона (Shake-to-Stop)")
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun requestNeededPermissions() {
        if (Build.VERSION.SDK_INT < 23) return
        val perms = mutableListOf(
            "android.permission.RECORD_AUDIO",
            "android.permission.CALL_PHONE",
            "android.permission.SEND_SMS",
            "android.permission.READ_SMS",
            "android.permission.READ_CALL_LOG",
            "android.permission.READ_CONTACTS",
            "android.permission.WRITE_CONTACTS",
            "android.permission.READ_CALENDAR",
            "android.permission.WRITE_CALENDAR",
            "android.permission.CAMERA",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.ACCESS_COARSE_LOCATION"
        )
        if (Build.VERSION.SDK_INT >= 33) {
            perms.add("android.permission.POST_NOTIFICATIONS")
        }
        val missing = perms.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            requestPermissions(missing.toTypedArray(), REQ_PERMS)
        }
    }

    private fun startVoiceRecognition(localeTag: String) {
        if (Build.VERSION.SDK_INT >= 23 &&
            checkSelfPermission("android.permission.RECORD_AUDIO") != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf("android.permission.RECORD_AUDIO"), REQ_PERMS)
            return
        }
        runOnUiThread {
            try {
                if (SpeechRecognizer.isRecognitionAvailable(this)) {
                    if (speechRecognizer == null) {
                        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                            override fun onReadyForSpeech(params: Bundle?) {}
                            override fun onBeginningOfSpeech() {}
                            override fun onRmsChanged(rmsdB: Float) {}
                            override fun onBufferReceived(buffer: ByteArray?) {}
                            override fun onEndOfSpeech() {}
                            override fun onError(error: Int) {
                                methodChannel?.invokeMethod(
                                    "onSpeechResult",
                                    mapOf("text" to "", "isFinal" to true)
                                )
                            }
                            override fun onResults(results: Bundle?) {
                                val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                                val top = list?.firstOrNull() ?: ""
                                methodChannel?.invokeMethod(
                                    "onSpeechResult",
                                    mapOf("text" to top, "isFinal" to true)
                                )
                            }
                            override fun onPartialResults(partialResults: Bundle?) {
                                val list = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                                val top = list?.firstOrNull() ?: ""
                                if (top.isNotEmpty()) {
                                    methodChannel?.invokeMethod(
                                        "onSpeechResult",
                                        mapOf("text" to top, "isFinal" to false)
                                    )
                                }
                            }
                            override fun onEvent(eventType: Int, params: Bundle?) {}
                        })
                    }
                    val recIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
                        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    }
                    speechRecognizer?.startListening(recIntent)
                } else {
                    val dialogIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
                        putExtra(RecognizerIntent.EXTRA_PROMPT, "Говорите команду для PulseAgent...")
                    }
                    @Suppress("DEPRECATION")
                    startActivityForResult(dialogIntent, REQ_SPEECH)
                }
            } catch (_: Exception) {
                methodChannel?.invokeMethod("onSpeechResult", mapOf("text" to "", "isFinal" to true))
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SPEECH) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val top = matches?.firstOrNull() ?: ""
                methodChannel?.invokeMethod("onSpeechResult", mapOf("text" to top, "isFinal" to true))
            } else {
                methodChannel?.invokeMethod("onSpeechResult", mapOf("text" to "", "isFinal" to true))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
            when (call.method) {
                "requestRuntimePermissions" -> {
                    requestNeededPermissions()
                    result.success(true)
                }
                "startListening" -> {
                    val locale = args["locale"]?.toString() ?: "ru-RU"
                    startVoiceRecognition(locale)
                    result.success(true)
                }
                "stopListening" -> {
                    runOnUiThread {
                        try {
                            speechRecognizer?.stopListening()
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "speakText" -> {
                    val text = args["text"]?.toString() ?: ""
                    if (text.isNotEmpty()) {
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "pulse_tts")
                    }
                    result.success(true)
                }
                "stopSpeaking" -> {
                    tts?.stop()
                    result.success(true)
                }
                "isAccessibilityEnabled" -> {
                    result.success(AgentAccessibilityService.instance != null)
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "toggleOverlayButton" -> {
                    val show = args["show"] as? Boolean ?: false
                    val svcIntent = Intent(this, OverlayButtonService::class.java)
                    if (show) {
                        startService(svcIntent)
                    } else {
                        stopService(svcIntent)
                    }
                    result.success(true)
                }
                "openNotificationListenerSettings" -> {
                    startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
                    result.success(true)
                }
                "getScreenTree" -> {
                    val tree = AgentAccessibilityService.instance?.dumpUiTree() ?: ""
                    result.success(tree)
                }
                "getActivePackage" -> {
                    val pkg = AgentAccessibilityService.instance?.getActivePackageName() ?: ""
                    result.success(pkg)
                }
                "tapElement" -> {
                    val index = (args["index"] as? Number)?.toInt() ?: 0
                    val x = (args["x"] as? Number)?.toFloat()
                    val y = (args["y"] as? Number)?.toFloat()
                    val ok = AgentAccessibilityService.instance?.tapNodeByIndex(index, x, y) ?: false
                    result.success(ok)
                }
                "inputText" -> {
                    val index = (args["index"] as? Number)?.toInt() ?: 0
                    val text = args["text"]?.toString() ?: ""
                    val ok = AgentAccessibilityService.instance?.inputTextByIndex(index, text) ?: false
                    result.success(ok)
                }
                "scrollScreen" -> {
                    val dir = args["direction"]?.toString() ?: "down"
                    val ok = AgentAccessibilityService.instance?.scrollScreen(dir) ?: false
                    result.success(ok)
                }
                "globalNav" -> {
                    val nav = args["action"]?.toString() ?: "back"
                    val ok = AgentAccessibilityService.instance?.performGlobalNavigation(nav) ?: false
                    result.success(ok)
                }
                "longPressElement" -> {
                    val index = (args["index"] as? Number)?.toInt() ?: 0
                    val durationMs = (args["durationMs"] as? Number)?.toLong() ?: 800L
                    val ok = AgentAccessibilityService.instance?.longPressByIndex(index, durationMs) ?: false
                    result.success(ok)
                }
                "swipeGesture" -> {
                    val x1 = (args["x1"] as? Number)?.toFloat() ?: 500f
                    val y1 = (args["y1"] as? Number)?.toFloat() ?: 1400f
                    val x2 = (args["x2"] as? Number)?.toFloat() ?: 500f
                    val y2 = (args["y2"] as? Number)?.toFloat() ?: 400f
                    val durationMs = (args["durationMs"] as? Number)?.toLong() ?: 350L
                    val ok = AgentAccessibilityService.instance?.dispatchSwipe(x1, y1, x2, y2, durationMs) ?: false
                    result.success(ok)
                }
                "takeScreenshot" -> {
                    val msg = AgentAccessibilityService.instance?.triggerScreenshot()
                        ?: "AccessibilityService не активен"
                    result.success(msg)
                }
                "openApp" -> {
                    val pkg = args["package"]?.toString() ?: ""
                    val appName = args["appName"]?.toString() ?: ""
                    result.success(systemBridge.openApplication(pkg, appName))
                }
                "makeCall" -> {
                    result.success(systemBridge.makePhoneCall(args["number"]?.toString() ?: ""))
                }
                "callContact" -> {
                    result.success(systemBridge.callContactByName(args["name"]?.toString() ?: ""))
                }
                "endCall" -> {
                    result.success(systemBridge.endPhoneCall())
                }
                "openCallLog" -> {
                    result.success(systemBridge.openCallLog())
                }
                "sendSms" -> {
                    result.success(
                        systemBridge.sendSms(
                            args["number"]?.toString() ?: "",
                            args["text"]?.toString() ?: ""
                        )
                    )
                }
                "readSms" -> {
                    val limit = (args["limit"] as? Number)?.toInt() ?: 5
                    result.success(systemBridge.readRecentSms(limit))
                }
                "setAlarm" -> {
                    val hour = (args["hour"] as? Number)?.toInt() ?: 7
                    val minute = (args["minute"] as? Number)?.toInt() ?: 0
                    val label = args["label"]?.toString() ?: "PulseAgent"
                    val days = (args["days"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() } ?: emptyList()
                    val vibrate = args["vibrate"] as? Boolean ?: true
                    result.success(systemBridge.setAlarm(hour, minute, label, days, vibrate))
                }
                "dismissAlarm" -> {
                    result.success(systemBridge.dismissAlarm())
                }
                "showAlarms" -> {
                    result.success(systemBridge.showAlarms())
                }
                "setTimer" -> {
                    val seconds = (args["seconds"] as? Number)?.toInt() ?: 60
                    val label = args["label"]?.toString() ?: "Таймер"
                    result.success(systemBridge.setTimer(seconds, label))
                }
                "openStopwatch" -> {
                    result.success(systemBridge.openStopwatch())
                }
                "createReminder" -> {
                    result.success(
                        systemBridge.createReminder(
                            title = args["title"]?.toString() ?: "Напоминание",
                            datetimeIso = args["datetime"]?.toString() ?: "",
                            description = args["description"]?.toString() ?: "",
                            minutesBefore = (args["minutesBefore"] as? Number)?.toInt() ?: 10
                        )
                    )
                }
                "createCalendarEvent" -> {
                    result.success(
                        systemBridge.createCalendarEvent(
                            title = args["title"]?.toString() ?: "Событие",
                            startIso = args["start"]?.toString() ?: "",
                            endIso = args["end"]?.toString() ?: "",
                            location = args["location"]?.toString() ?: "",
                            description = args["description"]?.toString() ?: ""
                        )
                    )
                }
                "getCalendarEvents" -> {
                    val days = (args["days"] as? Number)?.toInt() ?: 7
                    result.success(systemBridge.getUpcomingEvents(days))
                }
                "findContact" -> {
                    result.success(systemBridge.findContactByName(args["name"]?.toString() ?: ""))
                }
                "createContact" -> {
                    result.success(
                        systemBridge.insertContactIntent(
                            args["name"]?.toString() ?: "",
                            args["phone"]?.toString() ?: ""
                        )
                    )
                }
                "readNotifications" -> {
                    result.success(NotificationReaderService.dumpCurrentNotifications())
                }
                "dismissNotifications" -> {
                    NotificationReaderService.instance?.cancelAllNotifications()
                    result.success("Уведомления отклонены")
                }
                "setVolume" -> {
                    val stream = args["stream"]?.toString() ?: "music"
                    val level = (args["level"] as? Number)?.toInt() ?: 50
                    result.success(systemBridge.setVolume(stream, level))
                }
                "setBrightness" -> {
                    val level = (args["level"] as? Number)?.toInt() ?: 80
                    result.success(systemBridge.setBrightness(level))
                }
                "toggleWifi" -> {
                    result.success(systemBridge.openWifiPanel())
                }
                "toggleBluetooth" -> {
                    result.success(systemBridge.openBluetoothSettings())
                }
                "toggleAirplane" -> {
                    result.success(systemBridge.openAirplaneSettings())
                }
                "toggleDnd" -> {
                    val state = args["state"] as? Boolean ?: true
                    result.success(systemBridge.setDoNotDisturb(state))
                }
                "toggleFlashlight" -> {
                    val state = args["state"] as? Boolean ?: true
                    result.success(systemBridge.setFlashlight(state))
                }
                "vibrate" -> {
                    val ms = (args["ms"] as? Number)?.toLong() ?: 500L
                    result.success(systemBridge.vibrateDevice(ms))
                }
                "openPowerSaver" -> {
                    result.success(systemBridge.openBatterySaverSettings())
                }
                "openCamera" -> {
                    val mode = args["mode"]?.toString() ?: "photo"
                    result.success(systemBridge.openCamera(mode))
                }
                "recordAudio" -> {
                    val sec = (args["seconds"] as? Number)?.toInt() ?: 10
                    result.success(systemBridge.recordAudioShort(sec))
                }
                "openGallery" -> {
                    result.success(systemBridge.openGallery())
                }
                "controlMedia" -> {
                    val state = args["state"]?.toString() ?: "play"
                    result.success(systemBridge.dispatchMediaKey(state))
                }
                "openMusicTrack" -> {
                    val query = args["query"]?.toString() ?: ""
                    val app = args["app"]?.toString() ?: "spotify"
                    result.success(systemBridge.openMusicSearch(query, app))
                }
                "getNetworkStatus" -> {
                    result.success(systemBridge.getNetworkStatus())
                }
                "getBatteryInfo" -> {
                    result.success(systemBridge.getBatteryStatus())
                }
                "getLocation" -> {
                    result.success(systemBridge.getLastKnownLocation())
                }
                "openMap" -> {
                    result.success(systemBridge.openGeoMap(args["address"]?.toString() ?: ""))
                }
                "openTaxi" -> {
                    result.success(systemBridge.openTaxiApp(args["destination"]?.toString() ?: ""))
                }
                "listApps" -> {
                    result.success(systemBridge.listLaunchableApps())
                }
                "openPlayStore" -> {
                    result.success(systemBridge.openPlayStoreMarket(args["package"]?.toString() ?: ""))
                }
                "uninstallApp" -> {
                    result.success(systemBridge.requestUninstallPackage(args["package"]?.toString() ?: ""))
                }
                "openUrl" -> {
                    result.success(systemBridge.openBrowserUrl(args["url"]?.toString() ?: ""))
                }
                "composeEmail" -> {
                    result.success(
                        systemBridge.composeEmailIntent(
                            args["to"]?.toString() ?: "",
                            args["subject"]?.toString() ?: "",
                            args["body"]?.toString() ?: ""
                        )
                    )
                }
                "downloadFile" -> {
                    val url = args["url"]?.toString() ?: ""
                    val fileName = args["fileName"]?.toString() ?: "file"
                    result.success(systemBridge.enqueueDownload(url, fileName))
                }
                "openMessenger" -> {
                    val app = args["app"]?.toString() ?: "telegram"
                    val phone = args["phone"]?.toString() ?: ""
                    val text = args["text"]?.toString() ?: ""
                    result.success(systemBridge.openMessengerDeepLink(app, phone, text))
                }
                "updateAgentNotification" -> {
                    val title = args["title"]?.toString() ?: "PulseAgent"
                    val body = args["body"]?.toString() ?: ""
                    val step = (args["step"] as? Number)?.toInt() ?: 1
                    val maxSteps = (args["maxSteps"] as? Number)?.toInt() ?: 30
                    val ongoing = args["ongoing"] as? Boolean ?: false
                    AgentForegroundService.updateStatusNotification(
                        this,
                        title = title,
                        body = body,
                        step = step,
                        maxSteps = maxSteps,
                        ongoing = ongoing
                    )
                    result.success(true)
                }
                "scheduleDelayedGoal" -> {
                    val goal = args["goal"]?.toString() ?: ""
                    val delaySeconds = (args["delaySeconds"] as? Number)?.toInt() ?: 60
                    systemBridge.scheduleAlarmGoal(goal, delaySeconds)
                    result.success(true)
                }
                "schedulePeriodicGoal" -> {
                    val goal = args["goal"]?.toString() ?: ""
                    val intervalSeconds = (args["intervalSeconds"] as? Number)?.toInt() ?: 86400
                    systemBridge.schedulePeriodicGoal(goal, intervalSeconds)
                    result.success(true)
                }
                "cancelScheduledGoals" -> {
                    systemBridge.cancelScheduledGoals()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
