#!/usr/bin/env python3
import os, re, sys

APP = "android/app"
MANIFEST = APP + "/src/main/AndroidManifest.xml"

def die(msg):
    print("::error::" + msg)
    sys.exit(1)

# ---------- манифест ----------
if not os.path.exists(MANIFEST):
    die("AndroidManifest.xml не найден")
s = open(MANIFEST, encoding="utf-8").read()

perms = [
    "android.permission.INTERNET",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
]
add = ""
for p in perms:
    if '"%s"' % p not in s:
        add += '    <uses-permission android:name="%s"/>\n' % p
if "WRITE_EXTERNAL_STORAGE" not in s:
    add += ('    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="28"/>\n')
if add:
    s = s.replace("<application", add + "    <application", 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="VideoToMp3"', s, count=1)

if "ForegroundService" not in s:
    svc = ('        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" '
           'android:foregroundServiceType="dataSync" android:exported="false" />\n    ')
    s = s.replace("</application>", svc + "</application>", 1)
open(MANIFEST, "w", encoding="utf-8").write(s)
print("manifest patched")

# ---------- MainActivity: сохранение MP3 в общую «Музыку» (MediaStore) ----------
import glob
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
KOTLIN = '''package PKG_NAME

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vtomp3/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "saveToMusic" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (path == null || name == null) {
                            result.error("ARGS", "path/name missing", null)
                        } else {
                            Thread {
                                try {
                                    val uri = saveToMusic(path, name)
                                    runOnUiThread { result.success(uri) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("SAVE", e.message, null) }
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToMusic(path: String, name: String): String {
        val src = File(path)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                put(MediaStore.Audio.Media.MIME_TYPE, "audio/mpeg")
                put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/VideoToMp3")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw RuntimeException("insert failed")
            val out = resolver.openOutputStream(uri) ?: throw RuntimeException("no output stream")
            out.use { o -> FileInputStream(src).use { it.copyTo(o) } }
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "VideoToMp3")
            if (!dir.exists()) dir.mkdirs()
            val dst = File(dir, name)
            src.copyTo(dst, true)
            MediaScannerConnection.scanFile(this, arrayOf(dst.absolutePath), arrayOf("audio/mpeg"), null)
            return dst.absolutePath
        }
    }
}
'''.replace("PKG_NAME", pkg)
open(mdir + "/MainActivity.kt", "w", encoding="utf-8").write(KOTLIN)
print("MainActivity.kt written:", mdir)

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
    else:
        block = '''android {
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
    if "getByName(\"vtomp3Release\")" not in g and "signingConfigs.vtomp3Release" not in g:
        print("::warning::не нашёл debug-подпись в release — APK будет подписан debug-ключом")

open(f, "w", encoding="utf-8").write(g)

if not re.search(r'compileSdk\s*=\s*36', g):
    die("compileSdk 36 не применился в " + f)
print("gradle patched:", f)
