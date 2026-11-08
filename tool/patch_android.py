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
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_MEDIA_AUDIO",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
]
add = ""
for p in perms:
    if '"%s"' % p not in s:
        add += '    <uses-permission android:name="%s"/>\n' % p
if "READ_EXTERNAL_STORAGE" not in s:
    add += ('    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="32"/>\n')
if add:
    s = s.replace("<application", add + "    <application", 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="VideoToMp3"', s, count=1)

if "ForegroundService" not in s:
    svc = ('        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" '
           'android:foregroundServiceType="dataSync" android:exported="false" />\n    ')
    s = s.replace("</application>", svc + "</application>", 1)
open(MANIFEST, "w", encoding="utf-8").write(s)
print("manifest patched")

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
