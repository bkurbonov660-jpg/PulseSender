#!/bin/bash
set -e
APP=android/app
M=$APP/src/main/AndroidManifest.xml
[ -f "$M" ] || { echo "::error::AndroidManifest не найден"; exit 1; }

for PERM in 'android.permission.INTERNET' 'android.permission.READ_EXTERNAL_STORAGE' 'android.permission.READ_MEDIA_IMAGES' 'android.permission.READ_MEDIA_VIDEO' 'android.permission.FOREGROUND_SERVICE' 'android.permission.FOREGROUND_SERVICE_DATA_SYNC' 'android.permission.POST_NOTIFICATIONS'; do
  if ! grep -q "$PERM" "$M"; then
    sed -i "s#<application#    <uses-permission android:name=\"$PERM\"/>\n    <application#" "$M"
  fi
done

sed -i 's#android:label="[^"]*"#android:label="PulseSender"#' "$M"

python3 - "$M" << 'EOF_PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'ForegroundService' not in s:
    svc = '''        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />\n    '''
    s = s.replace('</application>', svc + '</application>', 1)
    open(p, 'w', encoding='utf-8').write(s)
EOF_PY

if [ -f "$APP/build.gradle.kts" ]; then
  F=$APP/build.gradle.kts
  if ! grep -q 'import java.util.Properties' "$F"; then sed -i '1i import java.util.Properties\nimport java.io.FileInputStream' "$F"; fi
  if ! grep -q 'pulseRelease' "$F"; then sed -i 's|^android {|android {\n    signingConfigs {\n        create("pulseRelease") {\n            val kp = Properties()\n            kp.load(FileInputStream(rootProject.file("key.properties")))\n            keyAlias = kp.getProperty("keyAlias")\n            keyPassword = kp.getProperty("keyPassword")\n            storeFile = file(kp.getProperty("storeFile"))\n            storePassword = kp.getProperty("storePassword")\n        }\n    }|' "$F"; fi
  sed -i 's|signingConfigs.getByName("debug")|signingConfigs.getByName("pulseRelease")\n            isMinifyEnabled = false\n            isShrinkResources = false|g' "$F"
  sed -i 's|minSdk = flutter.minSdkVersion|minSdk = 21|g' "$F"
elif [ -f "$APP/build.gradle" ]; then
  F=$APP/build.gradle
  if ! grep -q 'pulseRelease' "$F"; then sed -i 's|^android {|android {\n    signingConfigs {\n        pulseRelease {\n            def kp = new java.util.Properties()\n            kp.load(new java.io.FileInputStream(rootProject.file("key.properties")))\n            keyAlias kp.getProperty("keyAlias")\n            keyPassword kp.getProperty("keyPassword")\n            storeFile file(kp.getProperty("storeFile"))\n            storePassword kp.getProperty("storePassword")\n        }\n    }|' "$F"; fi
  sed -i 's|signingConfig signingConfigs.debug|signingConfig signingConfigs.pulseRelease\n            minifyEnabled false\n            shrinkResources false|g' "$F"
  sed -i 's|minSdkVersion flutter.minSdkVersion|minSdkVersion 21|g' "$F"
fi
