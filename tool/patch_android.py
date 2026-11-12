#!/usr/bin/env python3
import os, re, sys

APP = "android/app"
MANIFEST = APP + "/src/main/AndroidManifest.xml"

def die(msg):
    print("::error::" + msg)
    sys.exit(1)

if not os.path.exists(MANIFEST):
    die("AndroidManifest.xml не найден: " + MANIFEST)

s = open(MANIFEST, encoding="utf-8").read()
s = s.replace("com.pulseagent.pulse_agent", "com.pulseagent.app")

REQUIRED_PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECORD_AUDIO",
    "android.permission.SYSTEM_ALERT_WINDOW",
    "android.permission.QUERY_ALL_PACKAGES",
    "android.permission.CALL_PHONE",
    "android.permission.ANSWER_PHONE_CALLS",
    "android.permission.READ_CALL_LOG",
    "android.permission.SEND_SMS",
    "android.permission.READ_SMS",
    "android.permission.READ_CONTACTS",
    "android.permission.WRITE_CONTACTS",
    "android.permission.READ_CALENDAR",
    "android.permission.WRITE_CALENDAR",
    "com.android.alarm.permission.SET_ALARM",
    "android.permission.SET_ALARM",
    "android.permission.VIBRATE",
    "android.permission.CAMERA",
    "android.permission.FLASHLIGHT",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.MODIFY_AUDIO_SETTINGS",
    "android.permission.WRITE_SETTINGS",
    "android.permission.ACCESS_NOTIFICATION_POLICY",
    "android.permission.CHANGE_WIFI_STATE",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE",
    "android.permission.REQUEST_DELETE_PACKAGES",
]

perm_block = ""
for p in REQUIRED_PERMISSIONS:
    if f'"{p}"' not in s:
        perm_block += f'    <uses-permission android:name="{p}"/>\n'

if perm_block:
    s = s.replace("<application", perm_block + "    <application", 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="PulseAgent"', s, count=1)

SERVICES_BLOCK = '''
        <service
            android:name=".AgentAccessibilityService"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService"/>
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_service_config"/>
        </service>

        <service
            android:name=".NotificationReaderService"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService"/>
            </intent-filter>
        </service>

        <service
            android:name=".AgentForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false"/>

        <service
            android:name=".OverlayButtonService"
            android:exported="false"/>
'''

if "AgentAccessibilityService" not in s:
    s = s.replace("</application>", SERVICES_BLOCK + "\n    </application>", 1)

open(MANIFEST, "w", encoding="utf-8").write(s)
print("AndroidManifest.xml patched for PulseAgent")

kts = APP + "/build.gradle.kts"
grv = APP + "/build.gradle"
if os.path.exists(kts):
    gf, is_kts = kts, True
elif os.path.exists(grv):
    gf, is_kts = grv, False
else:
    die("build.gradle(.kts) не найден")

g = open(gf, encoding="utf-8").read()
g = re.sub(r'\bcompileSdk(Version)?\b[ \t]*=?[ \t]*[^\n};]+', 'compileSdk = 36', g)
g = re.sub(r'\btargetSdk(Version)?\b[ \t]*=?[ \t]*[^\n};]+', 'targetSdk = 36', g)
g = re.sub(r'\bminSdk(Version)?\b[ \t]*=?[ \t]*[^\n};]+', 'minSdk = 24', g)
g = re.sub(r'applicationId\s*=?\s*"[^"]+"', 'applicationId = "com.pulseagent.app"', g)
g = re.sub(r'namespace\s*=?\s*"[^"]+"', 'namespace = "com.pulseagent.app"', g)

if "pulseRelease" not in g and os.path.exists("android/key.properties"):
    if is_kts:
        if "import java.util.Properties" not in g:
            g = "import java.util.Properties\nimport java.io.FileInputStream\n" + g
        signing_block = '''android {
    signingConfigs {
        create("pulseRelease") {
            val kp = Properties()
            kp.load(FileInputStream(rootProject.file("key.properties")))
            keyAlias = kp.getProperty("keyAlias")
            keyPassword = kp.getProperty("keyPassword")
            storeFile = file(kp.getProperty("storeFile"))
            storePassword = kp.getProperty("storePassword")
        }
    }'''
        g = re.sub(r'^android\s*\{', lambda m: signing_block, g, count=1, flags=re.M)
        g = re.sub(
            r'signingConfig\s*=?\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = signingConfigs.getByName("pulseRelease")\n            isMinifyEnabled = false\n            isShrinkResources = false',
            g
        )
    else:
        signing_block = '''android {
    signingConfigs {
        pulseRelease {
            def kp = new java.util.Properties()
            kp.load(new java.io.FileInputStream(rootProject.file("key.properties")))
            keyAlias kp.getProperty("keyAlias")
            keyPassword kp.getProperty("keyPassword")
            storeFile file(kp.getProperty("storeFile"))
            storePassword kp.getProperty("storePassword")
        }
    }'''
        g = re.sub(r'^android\s*\{', lambda m: signing_block, g, count=1, flags=re.M)
        g = re.sub(
            r'signingConfig\s*=?\s*signingConfigs\.debug',
            'signingConfig signingConfigs.pulseRelease\n            minifyEnabled false\n            shrinkResources false',
            g
        )

open(gf, "w", encoding="utf-8").write(g)
if not re.search(r'compileSdk\s*=\s*36', g):
    die("compileSdk 36 не применился в " + gf)
print("Gradle patched successfully:", gf)
