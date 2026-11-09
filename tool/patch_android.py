#!/usr/bin/env python3
import os, re, sys, glob

APP = "android/app"
MANIFEST = APP + "/src/main/AndroidManifest.xml"

def die(msg):
    print("::error::" + msg)
    sys.exit(1)

if not os.path.exists(MANIFEST):
    die("AndroidManifest.xml не найден")
s = open(MANIFEST, encoding="utf-8").read()

# 1. Разрешения для фоновой загрузки, уведомлений, рингтона и медиа
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
    "android.permission.WRITE_SETTINGS",
]
add = ""
for p in perms:
    if '"%s"' % p not in s:
        add += '    <uses-permission android:name="%s"/>\n' % p
if "WRITE_EXTERNAL_STORAGE" not in s:
    add += ('    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="29"/>\n')
if "READ_EXTERNAL_STORAGE" not in s:
    add += ('    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="32"/>\n')
if add:
    s = s.replace("<application", add + "    <application", 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="VideoToMp3"', s, count=1)

# Обязательно android:extractNativeLibs="true" для работы встроенного Python + yt-dlp + ffmpeg
if 'android:extractNativeLibs' in s:
    s = re.sub(r'android:extractNativeLibs="[^"]*"', 'android:extractNativeLibs="true"', s)
else:
    s = s.replace("<application", '<application\n        android:extractNativeLibs="true"\n        android:requestLegacyExternalStorage="true"', 1)

# Регистрируем:
# - ShareDialogActivity (прозрачное мини-окошко поверх YouTube/TikTok/Instagram в меню «Поделиться»)
# - DownloadForegroundService (фоновая загрузка и конвертация без открытия приложения, с прогрессом в шторке)
extra_components = '''
        <activity
            android:name=".ShareDialogActivity"
            android:label="Скачать Видео / MP3"
            android:theme="@android:style/Theme.DeviceDefault.Dialog.NoActionBar"
            android:excludeFromRecents="true"
            android:taskAffinity=""
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
        </activity>

        <service
            android:name=".DownloadForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />

        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
'''

if "ShareDialogActivity" not in s:
    s = s.replace("</application>", extra_components + "\n    </application>", 1)

open(MANIFEST, "w", encoding="utf-8").write(s)
print("manifest patched with ShareDialogActivity, extractNativeLibs=true, and DownloadForegroundService")

# ---------- Нативный Kotlin-код: MainActivity, ShareDialogActivity, DownloadForegroundService ----------
pkg, mdir = "com.videotomp3.video_to_mp3", None
for old in glob.glob(APP + "/src/main/**/MainActivity.*", recursive=True):
    txt = open(old, encoding="utf-8").read()
    m = re.search(r'^\s*package\s+([\w.]+)', txt, re.M)
    if m:
        pkg = m.group(1)
    mdir = os.path.dirname(old)
    os.remove(old)
if mdir is None:
    mdir = APP + "/src/main/kotlin/" + pkg.replace(".", "/")
os.makedirs(mdir, exist_ok=True)

MAIN_ACTIVITY_KT = r'''package PKG_NAME

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    companion object {
        var channel: MethodChannel? = null
        var pendingAction: Map<String, Any?>? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val openFile = intent.getStringExtra("open_file_path")
        if (!openFile.isNullOrEmpty()) {
            val ch = channel
            if (ch != null) {
                ch.invokeMethod("onOpenPlayerFile", openFile)
            } else {
                pendingAction = mapOf("type" to "open_player", "filePath" to openFile)
            }
            intent.removeExtra("open_file_path")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val mc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vtomp3/media")
        channel = mc

        mc.setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)

                "consumeInitialAction" -> {
                    val act = pendingAction
                    pendingAction = null
                    result.success(act)
                }

                "saveToMusic" -> {
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name")
                    if (path == null || name == null) {
                        result.error("ARGS", "path/name missing", null)
                    } else {
                        Thread {
                            try {
                                val uri = MediaStoreHelper.saveToMusic(applicationContext, path, name)
                                runOnUiThread { result.success(uri) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SAVE", e.message, null) }
                            }
                        }.start()
                    }
                }

                "saveToMovies" -> {
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name")
                    if (path == null || name == null) {
                        result.error("ARGS", "path/name missing", null)
                    } else {
                        Thread {
                            try {
                                val uri = MediaStoreHelper.saveToMovies(applicationContext, path, name)
                                runOnUiThread { result.success(uri) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SAVE_VID", e.message, null) }
                            }
                        }.start()
                    }
                }

                "setRingtone" -> {
                    val path = call.argument<String>("path")
                    val title = call.argument<String>("title") ?: "VideoToMp3 Ringtone"
                    if (path == null) {
                        result.success(false)
                    } else {
                        Thread {
                            val ok = MediaStoreHelper.setAsRingtone(this, path, title)
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                }

                "downloadUrlNative" -> {
                    val url = call.argument<String>("url") ?: ""
                    val mode = call.argument<String>("mode") ?: "mp3"
                    val bitrate = call.argument<Int>("bitrate") ?: 192
                    val outputDir = call.argument<String>("outputDir") ?: filesDir.absolutePath
                    Thread {
                        val map = NativeYtDlpEngine.downloadBlocking(
                            applicationContext,
                            url = url,
                            mode = mode,
                            bitrate = bitrate,
                            outputDir = outputDir
                        )
                        runOnUiThread { result.success(map) }
                    }.start()
                }

                "updateYtDlp" -> {
                    Thread {
                        val status = NativeYtDlpEngine.updateEngine(applicationContext)
                        runOnUiThread { result.success(status) }
                    }.start()
                }

                "showProgressNotification" -> {
                    val title = call.argument<String>("title") ?: "VideoToMp3"
                    val text = call.argument<String>("text") ?: ""
                    val progress = call.argument<Int>("progress") ?: 0
                    NotificationHelper.showProgress(applicationContext, 7001, title, text, progress)
                    result.success(true)
                }

                "showCompletedNotification" -> {
                    val title = call.argument<String>("title") ?: "Готово"
                    val filePath = call.argument<String>("filePath") ?: ""
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    NotificationHelper.showCompleted(applicationContext, title, filePath, isVideo)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}
'''.replace("PKG_NAME", pkg)

SHARE_DIALOG_KT = r'''package PKG_NAME

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.view.Window
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * Компактное светлое мини-окошко в стиле оригинального дизайна (#2E7D32 + белый фон).
 * Выскакивает поверх YouTube, TikTok или Instagram: «Видео или MP3?».
 * Выбрал — и оно мгновенно закрылось.
 */
class ShareDialogActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)

        val sharedText = intent?.getStringExtra(Intent.EXTRA_TEXT) ?: ""
        val extractedUrl = extractUrl(sharedText)

        if (extractedUrl.isNullOrEmpty()) {
            Toast.makeText(this, "Ссылка не найдена", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        val density = resources.displayMetrics.density
        fun dp(v: Int): Int = (v * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(14))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(16).toFloat()
                setStroke(dp(1), Color.parseColor("#E0E0E0"))
            }
        }

        val header = TextView(this).apply {
            text = "Видео или MP3?"
            setTextColor(Color.parseColor("#212121"))
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        root.addView(header)

        val sub = TextView(this).apply {
            text = extractedUrl
            setTextColor(Color.parseColor("#757575"))
            textSize = 11f
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER
            setPadding(0, dp(4), 0, dp(12))
        }
        root.addView(sub)

        fun styleBtn(bgHex: String): GradientDrawable {
            return GradientDrawable().apply {
                setColor(Color.parseColor(bgHex))
                cornerRadius = dp(10).toFloat()
            }
        }

        val btnMp3 = Button(this).apply {
            text = "Скачать MP3 (с обложкой)"
            isAllCaps = false
            setTextColor(Color.WHITE)
            textSize = 13f
            background = styleBtn("#2E7D32")
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setOnClickListener {
                startBackgroundJob(extractedUrl, "mp3")
                Toast.makeText(applicationContext, "Загрузка MP3 в фоне...", Toast.LENGTH_SHORT).show()
                finish()
            }
        }
        root.addView(btnMp3, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(42)
        ).apply { bottomMargin = dp(8) })

        val btnVideo = Button(this).apply {
            text = "Скачать Видео (без водяного знака)"
            isAllCaps = false
            setTextColor(Color.parseColor("#2E7D32"))
            textSize = 13f
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#E8F5E9"))
                cornerRadius = dp(10).toFloat()
                setStroke(dp(1), Color.parseColor("#2E7D32"))
            }
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setOnClickListener {
                startBackgroundJob(extractedUrl, "video")
                Toast.makeText(applicationContext, "Загрузка видео в фоне...", Toast.LENGTH_SHORT).show()
                finish()
            }
        }
        root.addView(btnVideo, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(42)
        ).apply { bottomMargin = dp(6) })

        val btnCancel = TextView(this).apply {
            text = "Отмена"
            setTextColor(Color.parseColor("#9E9E9E"))
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(0, dp(4), 0, dp(2))
            setOnClickListener { finish() }
        }
        root.addView(btnCancel)

        setContentView(root, ViewGroup.LayoutParams(dp(290), ViewGroup.LayoutParams.WRAP_CONTENT))
        window?.setBackgroundDrawableResource(android.R.color.transparent)
    }

    private fun startBackgroundJob(url: String, mode: String) {
        val svcIntent = Intent(applicationContext, DownloadForegroundService::class.java).apply {
            putExtra("url", url)
            putExtra("mode", mode)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(svcIntent)
        } else {
            applicationContext.startService(svcIntent)
        }
    }

    private fun extractUrl(text: String): String? {
        val tokens = text.split(' ', ',', ';', '<', '>', '(', ')')
        for (tok in tokens) {
            for (line in tok.lines()) {
                val cleaned = line.trim { it.isWhitespace() || it.code == 34 || it.code == 39 }
                val httpIdx = cleaned.indexOf("http")
                if (httpIdx >= 0) {
                    val sub = cleaned.substring(httpIdx)
                    if (sub.startsWith("http://") || sub.startsWith("https://")) {
                        return sub
                    }
                }
            }
        }
        return null
    }
}
'''.replace("PKG_NAME", pkg)

FOREGROUND_SERVICE_KT = r'''package PKG_NAME

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors

/**
 * Нативный фоновый сервис загрузки и конвертации:
 * Работает ДАЖЕ когда основное Flutter-приложение полностью закрыто!
 * Качает YouTube / TikTok (без водяного знака) / Instagram,
 * показывает прогресс в шторке уведомлений, сохраняет в Музыку/Галерею,
 * записывает в историю приложения и присылает уведомление «Готово» с открытием по нажатию.
 */
class DownloadForegroundService : Service() {
    private val executor = Executors.newSingleThreadExecutor()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val url = intent?.getStringExtra("url") ?: ""
        val mode = intent?.getStringExtra("mode") ?: "mp3"

        NotificationHelper.ensureChannels(applicationContext)
        val initialNotif = NotificationHelper.buildProgressNotification(
            applicationContext,
            title = if (mode == "mp3") "Подготовка MP3..." else "Подготовка видео...",
            text = url,
            progress = 5
        )
        try {
            startForeground(7001, initialNotif)
        } catch (_: Exception) {}

        if (url.isNotEmpty()) {
            executor.submit {
                try {
                    processDownloadJob(url, mode)
                } finally {
                    try {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                    } catch (_: Exception) {}
                    stopSelf(startId)
                }
            }
        } else {
            stopSelf(startId)
        }

        return START_NOT_STICKY
    }

    private fun processDownloadJob(url: String, mode: String) {
        val appFlutterDir = File(filesDir.parentFile, "app_flutter")
        val outSub = if (mode == "video") File(appFlutterDir, "videos") else File(appFlutterDir, "mp3")
        if (!outSub.exists()) outSub.mkdirs()

        NotificationHelper.showProgress(
            applicationContext,
            7001,
            if (mode == "mp3") "Скачивание и конвертация MP3" else "Скачивание видео без водяного знака",
            url,
            15
        )

        val res = NativeYtDlpEngine.downloadBlocking(
            applicationContext,
            url = url,
            mode = mode,
            bitrate = 192,
            outputDir = outSub.absolutePath
        ) { prog, line ->
            NotificationHelper.showProgress(
                applicationContext,
                7001,
                if (mode == "mp3") "Загрузка MP3 (${prog}%)" else "Загрузка Видео (${prog}%)",
                line,
                prog
            )
        }

        val path = res?.get("filePath") as? String
        val title = (res?.get("title") as? String) ?: "Track_${System.currentTimeMillis()}"
        val uploader = (res?.get("uploader") as? String) ?: "VideoToMp3"

        if (path != null && File(path).exists()) {
            val isVid = mode == "video"
            try {
                if (isVid) {
                    MediaStoreHelper.saveToMovies(applicationContext, path, File(path).name)
                } else {
                    MediaStoreHelper.saveToMusic(applicationContext, path, File(path).name)
                }
            } catch (_: Exception) {}

            appendHistoryRecord(
                filePath = path,
                title = title,
                artist = uploader,
                isVideo = isVid
            )

            MainActivity.channel?.let { ch ->
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try {
                        ch.invokeMethod("onBackgroundDownloadFinished", path)
                    } catch (_: Exception) {}
                }
            }

            NotificationHelper.showCompleted(
                applicationContext,
                title = "Готово: $title",
                filePath = path,
                isVideo = isVid
            )
        } else {
            NotificationHelper.showError(
                applicationContext,
                title = "Не удалось скачать ссылку",
                text = url
            )
        }
    }

    private fun appendHistoryRecord(filePath: String, title: String, artist: String, isVideo: Boolean) {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val key = "flutter.conversion_history_v2"
            val itemJson = JSONObject().apply {
                put("id", "${System.currentTimeMillis()}")
                put("fileName", File(filePath).name)
                put("filePath", filePath)
                put("createdAt", java.time.Instant.now().toString())
                put("bitrateKbps", 192)
                put("title", title)
                put("artist", artist)
                put("isVideo", isVideo)
                put("sourceType", "share")
            }.toString()

            val currentSet = prefs.getStringSet(key, null)?.toMutableSet()
            if (currentSet != null) {
                currentSet.add(itemJson)
                prefs.edit().putStringSet(key, currentSet).apply()
            }
        } catch (_: Exception) {}
    }
}

object NativeYtDlpEngine {
    @Volatile
    private var initialized = false

    @Synchronized
    fun ensureInit(context: Context) {
        if (initialized) return
        try {
            YoutubeDL.getInstance().init(context)
            try {
                FFmpeg.getInstance().init(context)
            } catch (_: Exception) {}
            initialized = true
        } catch (_: Exception) {}
    }

    fun updateEngine(context: Context): String {
        ensureInit(context)
        return try {
            val st = YoutubeDL.getInstance().updateYoutubeDL(context, YoutubeDL.UpdateChannel.NIGHTLY)
            st?.name ?: "UPDATED"
        } catch (e: Exception) {
            "OK (${e.message})"
        }
    }

    fun downloadBlocking(
        context: Context,
        url: String,
        mode: String,
        bitrate: Int,
        outputDir: String,
        onProgress: ((Int, String) -> Unit)? = null
    ): Map<String, Any?>? {
        val lower = url.lowercase()

        // 1. Для TikTok сначала используем прямой TikWM HD API без водяного знака (работает мгновенно и без блокировок)
        if (lower.contains("tiktok.com") || lower.contains("vm.tiktok") || lower.contains("vt.tiktok")) {
            val tik = tryTikWmDownload(url, mode, outputDir, onProgress)
            if (tik != null) return tik
        }

        // 2. Встроенный движок yt-dlp + FFmpeg (youtubedl-android 0.18.1) для YouTube, Instagram, TikTok и любых сайтов
        ensureInit(context)
        try {
            val dir = File(outputDir)
            if (!dir.exists()) dir.mkdirs()

            val stamp = System.currentTimeMillis()
            val outTemplate = File(dir, "%(title).45s_$stamp.%(ext)s").absolutePath

            val req = YoutubeDLRequest(url)
            req.addOption("--no-mtime")
            req.addOption("--no-playlist")
            req.addOption("-o", outTemplate)

            if (mode == "mp3") {
                req.addOption("-x")
                req.addOption("--audio-format", "mp3")
                req.addOption("--audio-quality", "${bitrate}K")
                req.addOption("--add-metadata")
            } else {
                req.addOption("-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best")
                req.addOption("--merge-output-format", "mp4")
            }

            var title = "Media_$stamp"
            var uploader = "VideoToMp3"
            var thumb: String? = null
            try {
                val info = YoutubeDL.getInstance().getInfo(url)
                if (!info.title.isNullOrEmpty()) title = info.title!!
                if (!info.uploader.isNullOrEmpty()) uploader = info.uploader!!
                thumb = info.thumbnail
            } catch (_: Exception) {}

            YoutubeDL.getInstance().execute(req, null) { progress, _, line ->
                val p = progress.toInt().coerceIn(5, 99)
                onProgress?.invoke(p, line ?: title)
            }

            val created = dir.listFiles()
                ?.filter { it.isFile && it.name.contains("_$stamp") && !it.name.endsWith(".part") }
                ?.maxByOrNull { it.lastModified() }

            if (created != null && created.exists()) {
                return mapOf(
                    "filePath" to created.absolutePath,
                    "title" to title,
                    "uploader" to uploader,
                    "thumbnail" to thumb
                )
            }
        } catch (_: Exception) {}

        return null
    }

    private fun tryTikWmDownload(
        videoUrl: String,
        mode: String,
        outputDir: String,
        onProgress: ((Int, String) -> Unit)?
    ): Map<String, Any?>? {
        return try {
            onProgress?.invoke(15, "TikTok: запрос HD без водяного знака...")
            val api = URL("https://www.tikwm.com/api/")
            val conn = (api.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 15000
                readTimeout = 20000
                setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                setRequestProperty("User-Agent", "Mozilla/5.0")
            }
            val body = "url=" + URLEncoder.encode(videoUrl, "UTF-8") + "&hd=1"
            OutputStreamWriter(conn.outputStream).use { it.write(body) }

            val respText = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
            val root = JSONObject(respText)
            if (root.optInt("code", -1) != 0) return null
            val data = root.optJSONObject("data") ?: return null

            val rawTitle = data.optString("title", "TikTok_${System.currentTimeMillis()}")
            val author = data.optJSONObject("author")?.optString("nickname", "TikTok") ?: "TikTok"
            val cover = data.optString("origin_cover", data.optString("cover", ""))

            val targetUrl = if (mode == "mp3" && data.optString("music", "").startsWith("http")) {
                data.optString("music")
            } else {
                val p = data.optString("hdplay").ifEmpty { data.optString("play") }
                if (p.startsWith("http")) p else "https://www.tikwm.com$p"
            }
            if (targetUrl.isEmpty()) return null

            val ext = if (mode == "mp3" && targetUrl.contains(".mp3")) "mp3" else "mp4"
            val safe = rawTitle.replace(Regex("[^a-zA-Z0-9а-яА-ЯёЁ_-]"), "_").take(35).ifEmpty { "tiktok" }
            val outFile = File(outputDir, "${safe}_${System.currentTimeMillis()}.$ext")

            val dlConn = (URL(targetUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 20000
                readTimeout = 40000
                setRequestProperty("User-Agent", "Mozilla/5.0")
            }
            val total = dlConn.contentLength
            var downloaded = 0L
            dlConn.inputStream.use { input ->
                FileOutputStream(outFile).use { output ->
                    val buf = ByteArray(16 * 1024)
                    var n: Int
                    while (input.read(buf).also { n = it } != -1) {
                        output.write(buf, 0, n)
                        downloaded += n
                        if (total > 0) {
                            val pct = ((downloaded * 100) / total).toInt().coerceIn(20, 95)
                            onProgress?.invoke(pct, rawTitle)
                        }
                    }
                }
            }

            if (outFile.exists() && outFile.length() > 1024) {
                mapOf(
                    "filePath" to outFile.absolutePath,
                    "title" to rawTitle,
                    "uploader" to author,
                    "thumbnail" to cover
                )
            } else null
        } catch (_: Exception) {
            null
        }
    }
}

object NotificationHelper {
    private const val CH_PROGRESS = "vtomp3_progress"
    private const val CH_DONE = "vtomp3_done"

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val chProg = NotificationChannel(
                CH_PROGRESS,
                "Загрузка и Конвертация",
                NotificationManager.IMPORTANCE_LOW
            )
            val chDone = NotificationChannel(
                CH_DONE,
                "Готовые файлы VideoToMp3",
                NotificationManager.IMPORTANCE_HIGH
            )
            nm.createNotificationChannel(chProg)
            nm.createNotificationChannel(chDone)
        }
    }

    fun buildProgressNotification(context: Context, title: String, text: String, progress: Int): Notification {
        ensureChannels(context)
        val openIntent = Intent(context, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            context,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(context, CH_PROGRESS)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setProgress(100, progress.coerceIn(0, 100), progress <= 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pi)
            .build()
    }

    fun showProgress(context: Context, id: Int, title: String, text: String, progress: Int) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, buildProgressNotification(context, title, text, progress))
    }

    fun showCompleted(context: Context, title: String, filePath: String, isVideo: Boolean) {
        ensureChannels(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(7001)

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_file_path", filePath)
        }
        val pi = PendingIntent.getActivity(
            context,
            (System.currentTimeMillis() % 10000).toInt(),
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, CH_DONE)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(
                if (isVideo) "Нажмите, чтобы открыть видео без водяного знака"
                else "Нажмите, чтобы открыть в плеере (MP3 + обложка)"
            )
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pi)
            .build()

        nm.notify((System.currentTimeMillis() % 10000).toInt() + 8000, notif)
    }

    fun showError(context: Context, title: String, text: String) {
        ensureChannels(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(7001)
        val notif = NotificationCompat.Builder(context, CH_DONE)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .build()
        nm.notify(7999, notif)
    }
}

object MediaStoreHelper {
    fun saveToMusic(context: Context, path: String, name: String): String {
        val src = File(path)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                put(MediaStore.Audio.Media.MIME_TYPE, "audio/mpeg")
                put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/VideoToMp3")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw RuntimeException("insert failed")
            resolver.openOutputStream(uri)?.use { o -> FileInputStream(src).use { it.copyTo(o) } }
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "VideoToMp3")
            if (!dir.exists()) dir.mkdirs()
            val dst = File(dir, name)
            src.copyTo(dst, true)
            MediaScannerConnection.scanFile(context, arrayOf(dst.absolutePath), arrayOf("audio/mpeg"), null)
            return dst.absolutePath
        }
    }

    fun saveToMovies(context: Context, path: String, name: String): String {
        val src = File(path)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, name)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/VideoToMp3")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw RuntimeException("insert video failed")
            resolver.openOutputStream(uri)?.use { o -> FileInputStream(src).use { it.copyTo(o) } }
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "VideoToMp3")
            if (!dir.exists()) dir.mkdirs()
            val dst = File(dir, name)
            src.copyTo(dst, true)
            MediaScannerConnection.scanFile(context, arrayOf(dst.absolutePath), arrayOf("video/mp4"), null)
            return dst.absolutePath
        }
    }

    fun setAsRingtone(activity: Activity, path: String, title: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.System.canWrite(activity)) {
                val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                    data = Uri.parse("package:" + activity.packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
                return false
            }
            val src = File(path)
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, src.name)
                put(MediaStore.MediaColumns.TITLE, title)
                put(MediaStore.MediaColumns.MIME_TYPE, "audio/mpeg")
                put(MediaStore.Audio.Media.IS_RINGTONE, true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_RINGTONES)
                }
            }
            val resolver = activity.contentResolver
            val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values) ?: return false
            resolver.openOutputStream(uri)?.use { o -> FileInputStream(src).use { it.copyTo(o) } }
            RingtoneManager.setActualDefaultRingtoneUri(activity, RingtoneManager.TYPE_RINGTONE, uri)
            true
        } catch (_: Exception) {
            false
        }
    }
}
'''.replace("PKG_NAME", pkg)

open(mdir + "/MainActivity.kt", "w", encoding="utf-8").write(MAIN_ACTIVITY_KT)
open(mdir + "/ShareDialogActivity.kt", "w", encoding="utf-8").write(SHARE_DIALOG_KT)
open(mdir + "/DownloadForegroundService.kt", "w", encoding="utf-8").write(FOREGROUND_SERVICE_KT)
print("Kotlin files written:", mdir)

# ---------- gradle приложения ----------
kts = APP + "/build.gradle.kts"
grv = APP + "/build.gradle"
if os.path.exists(kts):
    f, is_kts = kts, True
elif os.path.exists(grv):
    f, is_kts = grv, False
else:
    die("build.gradle(.kts) приложения не найден")

g = open(f, encoding="utf-8").read()
g = re.sub(r'\bcompileSdk(Version)?\b[ \t]*=?[ \t]*[^\n};]+', 'compileSdk = 36', g)
g = re.sub(r'\btargetSdk(Version)?\b[ \t]*=?[ \t]*[^\n};]+', 'targetSdk = 36', g)
g = re.sub(r'\bminSdk(Version)?\b[ \t]*=?[ \t]*[^\n};]+', 'minSdk = 24', g)

if "vtomp3Release" not in g:
    if is_kts:
        if "import java.util.Properties" not in g:
            g = "import java.util.Properties\nimport java.io.FileInputStream\n" + g
        block = '''android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += setOf("**/libc++_shared.so")
            keepDebugSymbols += setOf("**/*.zip.so", "**/libffmpeg.zip.so", "**/libpython.zip.so")
        }
    }
    signingConfigs {
        create("vtomp3Release") {
            val kp = Properties()
            kp.load(FileInputStream(rootProject.file("key.properties")))
            keyAlias = kp.getProperty("keyAlias")
            keyPassword = kp.getProperty("keyPassword")
            storeFile = file(kp.getProperty("storeFile"))
            storePassword = kp.getProperty("storePassword")
        }
    }'''
        g = re.sub(r'^android\s*\{', lambda m: block, g, count=1, flags=re.M)
        g = re.sub(r'signingConfig\s*=?\s*signingConfigs\.getByName\("debug"\)',
                   'signingConfig = signingConfigs.getByName("vtomp3Release")\n'
                   '            isMinifyEnabled = false\n'
                   '            isShrinkResources = false', g)
        deps_block = '''
dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
}
'''
        if "youtubedl-android" not in g:
            g += "\n" + deps_block
    else:
        block = '''android {
    packagingOptions {
        jniLibs {
            useLegacyPackaging true
            keepDebugSymbols += ["**/*.zip.so", "**/libffmpeg.zip.so", "**/libpython.zip.so"]
        }
        pickFirst "**/libc++_shared.so"
        doNotStrip "**/*.zip.so"
    }
    signingConfigs {
        vtomp3Release {
            def kp = new java.util.Properties()
            kp.load(new java.io.FileInputStream(rootProject.file("key.properties")))
            keyAlias kp.getProperty("keyAlias")
            keyPassword kp.getProperty("keyPassword")
            storeFile file(kp.getProperty("storeFile"))
            storePassword kp.getProperty("storePassword")
        }
    }'''
        g = re.sub(r'^android\s*\{', lambda m: block, g, count=1, flags=re.M)
        g = re.sub(r'signingConfig\s*=?\s*signingConfigs\.debug',
                   'signingConfig signingConfigs.vtomp3Release\n'
                   '            minifyEnabled false\n'
                   '            shrinkResources false', g)
        deps_block = '''
dependencies {
    implementation "io.github.junkfood02.youtubedl-android:library:0.18.1"
    implementation "io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1"
}
'''
        if "youtubedl-android" not in g:
            g += "\n" + deps_block

open(f, "w", encoding="utf-8").write(g)

if not re.search(r'compileSdk\s*=\s*36', g):
    die("compileSdk 36 не применился в " + f)
print("gradle patched with youtubedl-android 0.18.1 and compileSdk 36:", f)
