package com.pulseagent.app

import android.app.AlarmManager
import android.app.DownloadManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraManager
import android.location.LocationManager
import android.media.AudioManager
import android.media.MediaRecorder
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import android.telephony.SmsManager
import android.view.KeyEvent
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

class SystemActionBridge(private val context: Context) {

    fun openApplication(packageName: String, appName: String): Boolean {
        val pm = context.packageManager
        if (packageName.isNotEmpty()) {
            val launch = pm.getLaunchIntentForPackage(packageName)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(launch)
                return true
            }
        }
        if (appName.isNotEmpty()) {
            val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val apps = pm.queryIntentActivities(mainIntent, 0)
            val match = apps.firstOrNull {
                it.loadLabel(pm).toString().contains(appName, ignoreCase = true)
            }
            if (match != null) {
                val launch = pm.getLaunchIntentForPackage(match.activityInfo.packageName)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(launch)
                    return true
                }
            }
        }
        return false
    }

    fun openBrowserUrl(url: String): String {
        if (url.isBlank()) return "URL пуст"
        return try {
            val uri = Uri.parse(url)
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Открыт URL: $url"
        } catch (e: Exception) {
            "Ошибка открытия URL: ${e.message}"
        }
    }

    fun composeEmailIntent(to: String, subject: String, body: String): String {
        return try {
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("mailto:")
                putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, body)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Открыто окно письма для $to"
        } catch (e: Exception) {
            "Ошибка открытия почты: ${e.message}"
        }
    }

    fun openTaxiApp(destination: String): String {
        return try {
            val uri = Uri.parse(
                "uber://?action=setPickup&pickup=my_location&dropoff[formatted_address]=${Uri.encode(destination)}"
            )
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Открыто приложение такси ($destination)"
        } catch (_: Exception) {
            openGeoMap(destination)
        }
    }

    fun makePhoneCall(number: String): String {
        if (number.isBlank()) return "Номер не указан"
        return try {
            val callIntent = Intent(Intent.ACTION_CALL, Uri.parse("tel:${Uri.encode(number)}")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(callIntent)
            "Звонок на номер $number"
        } catch (_: SecurityException) {
            val dialIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${Uri.encode(number)}")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(dialIntent)
            "Открыт номеронабиратель для $number"
        }
    }

    fun callContactByName(name: String): String {
        val phone = lookupContactNumber(name)
        return if (phone != null) {
            makePhoneCall(phone)
        } else {
            "Контакт '$name' не найден в телефонной книге"
        }
    }

    fun endPhoneCall(): String {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                @Suppress("DEPRECATION")
                tm.endCall()
                "Вызов завершён"
            } else {
                "Завершение вызова требует Android 9+"
            }
        } catch (e: Exception) {
            "Не удалось сбросить вызов: ${e.message}"
        }
    }

    fun openCallLog(): String {
        val intent = Intent(Intent.ACTION_VIEW, CallLog.Calls.CONTENT_URI).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыт журнал вызовов"
    }

    fun sendSms(number: String, text: String): String {
        if (number.isBlank()) return "Номер получателя SMS пуст"
        return try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            smsManager.sendTextMessage(number, null, text, null, null)
            "SMS отправлено на $number"
        } catch (_: Exception) {
            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${Uri.encode(number)}")).apply {
                putExtra("sms_body", text)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Открыто приложение Сообщения с текстом для $number"
        }
    }

    fun readRecentSms(limit: Int): String {
        return try {
            val sb = StringBuilder()
            val cursor = context.contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY),
                null,
                null,
                "${Telephony.Sms.DATE} DESC"
            )
            cursor?.use {
                var count = 0
                while (it.moveToNext() && count < limit) {
                    val sender = it.getString(0) ?: "?"
                    val body = it.getString(1) ?: ""
                    sb.append("От $sender: $body\n")
                    count++
                }
            }
            if (sb.isEmpty()) "Входящих SMS нет" else sb.toString().trim()
        } catch (e: Exception) {
            "Нет разрешения READ_SMS: ${e.message}"
        }
    }

    fun setAlarm(
        hour: Int,
        minute: Int,
        label: String,
        days: List<Int>,
        vibrate: Boolean
    ): String {
        val calendarDays = ArrayList<Int>()
        for (d in days) {
            val calDay = when (d) {
                1 -> Calendar.MONDAY
                2 -> Calendar.TUESDAY
                3 -> Calendar.WEDNESDAY
                4 -> Calendar.THURSDAY
                5 -> Calendar.FRIDAY
                6 -> Calendar.SATURDAY
                7 -> Calendar.SUNDAY
                else -> d
            }
            calendarDays.add(calDay)
        }
        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
            putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
            putExtra(AlarmClock.EXTRA_MESSAGE, label)
            putExtra(AlarmClock.EXTRA_VIBRATE, vibrate)
            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            if (calendarDays.isNotEmpty()) {
                putExtra(AlarmClock.EXTRA_DAYS, calendarDays)
            }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return String.format(Locale.US, "Будильник установлен на %02d:%02d (%s)", hour, minute, label)
    }

    fun dismissAlarm(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(AlarmClock.ACTION_DISMISS_ALARM).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Открыто отключение будильника"
        } else {
            showAlarms()
        }
    }

    fun showAlarms(): String {
        val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыт список будильников"
    }

    fun setTimer(seconds: Int, label: String): String {
        val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
            putExtra(AlarmClock.EXTRA_LENGTH, seconds.coerceAtLeast(1))
            putExtra(AlarmClock.EXTRA_MESSAGE, label)
            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Таймер '$label' запущен на $seconds сек."
    }

    fun openStopwatch(): String {
        val intent = Intent(AlarmClock.ACTION_SHOW_TIMERS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            "Открыт секундомер / таймеры"
        } catch (_: Exception) {
            showAlarms()
        }
    }

    fun createReminder(
        title: String,
        datetimeIso: String,
        description: String,
        minutesBefore: Int
    ): String {
        val startMs = parseIsoMillis(datetimeIso) ?: (System.currentTimeMillis() + 3600_000L)
        val endMs = startMs + 1800_000L
        return try {
            val calId = getPrimaryCalendarId() ?: 1L
            val values = ContentValues().apply {
                put(CalendarContract.Events.DTSTART, startMs)
                put(CalendarContract.Events.DTEND, endMs)
                put(CalendarContract.Events.TITLE, title)
                put(CalendarContract.Events.DESCRIPTION, description)
                put(CalendarContract.Events.CALENDAR_ID, calId)
                put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            }
            val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            val eventId = uri?.lastPathSegment?.toLongOrNull()
            if (eventId != null) {
                val remValues = ContentValues().apply {
                    put(CalendarContract.Reminders.MINUTES, minutesBefore)
                    put(CalendarContract.Reminders.EVENT_ID, eventId)
                    put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                }
                context.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, remValues)
            }
            "Напоминание '$title' добавлено в Календарь"
        } catch (_: Exception) {
            val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
                putExtra(CalendarContract.Events.TITLE, title)
                putExtra(CalendarContract.Events.DESCRIPTION, description)
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Открыто создание напоминания '$title'"
        }
    }

    fun createCalendarEvent(
        title: String,
        startIso: String,
        endIso: String,
        location: String,
        description: String
    ): String {
        val startMs = parseIsoMillis(startIso) ?: (System.currentTimeMillis() + 3600_000L)
        val endMs = parseIsoMillis(endIso) ?: (startMs + 3600_000L)
        val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
            putExtra(CalendarContract.Events.TITLE, title)
            putExtra(CalendarContract.Events.EVENT_LOCATION, location)
            putExtra(CalendarContract.Events.DESCRIPTION, description)
            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Событие '$title' открыто в Календаре"
    }

    fun getUpcomingEvents(days: Int): String {
        return try {
            val now = System.currentTimeMillis()
            val end = now + days * 86400_000L
            val cursor = context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                arrayOf(CalendarContract.Events.TITLE, CalendarContract.Events.DTSTART),
                "${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} <= ?",
                arrayOf(now.toString(), end.toString()),
                "${CalendarContract.Events.DTSTART} ASC"
            )
            val sb = StringBuilder()
            val fmt = SimpleDateFormat("dd.MM HH:mm", Locale.getDefault())
            cursor?.use {
                while (it.moveToNext()) {
                    val t = it.getString(0) ?: "Без названия"
                    val dt = it.getLong(1)
                    sb.append("• ${fmt.format(dt)}: $t\n")
                }
            }
            if (sb.isEmpty()) "Событий на ближайшие $days дн. нет" else sb.toString().trim()
        } catch (e: Exception) {
            "Нет доступа к календарю: ${e.message}"
        }
    }

    private fun getPrimaryCalendarId(): Long? {
        val cursor = context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            null,
            null,
            null
        )
        cursor?.use {
            if (it.moveToFirst()) return it.getLong(0)
        }
        return null
    }

    private fun parseIsoMillis(iso: String): Long? {
        if (iso.isBlank()) return null
        return try {
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            fmt.parse(iso)?.time
        } catch (_: Exception) {
            null
        }
    }

    fun findContactByName(name: String): String {
        val phone = lookupContactNumber(name)
        return if (phone != null) "Найден контакт $name: $phone" else "Контакт '$name' не найден"
    }

    private fun lookupContactNumber(name: String): String? {
        if (name.isBlank()) return null
        return try {
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                arrayOf("%$name%"),
                null
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    return it.getString(1)
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    fun insertContactIntent(name: String, phone: String): String {
        val intent = Intent(Intent.ACTION_INSERT).apply {
            type = ContactsContract.Contacts.CONTENT_TYPE
            putExtra(ContactsContract.Intents.Insert.NAME, name)
            putExtra(ContactsContract.Intents.Insert.PHONE, phone)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыто сохранение контакта $name ($phone)"
    }

    fun setVolume(streamName: String, levelPercent: Int): String {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val streamType = when (streamName.lowercase()) {
            "ring", "call" -> AudioManager.STREAM_RING
            "alarm" -> AudioManager.STREAM_ALARM
            "notification" -> AudioManager.STREAM_NOTIFICATION
            else -> AudioManager.STREAM_MUSIC
        }
        val max = am.getStreamMaxVolume(streamType)
        val target = ((levelPercent.coerceIn(0, 100) / 100.0) * max).toInt()
        am.setStreamVolume(streamType, target, AudioManager.FLAG_SHOW_UI)
        return "Громкость ($streamName) установлена на $levelPercent%"
    }

    fun setBrightness(levelPercent: Int): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.System.canWrite(context)) {
            val value = ((levelPercent.coerceIn(0, 100) / 100.0) * 255).toInt()
            Settings.System.putInt(
                context.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                value
            )
            "Яркость экрана установлена на $levelPercent%"
        } else {
            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Предоставьте разрешение на изменение системных настроек для яркости"
        }
    }

    fun openWifiPanel(): String {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent(Settings.Panel.ACTION_WIFI)
        } else {
            Intent(Settings.ACTION_WIFI_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return "Открыта панель управления Wi-Fi"
    }

    fun openBluetoothSettings(): String {
        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыты настройки Bluetooth"
    }

    fun openAirplaneSettings(): String {
        val intent = Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыты настройки режима полёта"
    }

    fun setDoNotDisturb(enable: Boolean): String {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && nm.isNotificationPolicyAccessGranted) {
            nm.setInterruptionFilter(
                if (enable) NotificationManager.INTERRUPTION_FILTER_NONE
                else NotificationManager.INTERRUPTION_FILTER_ALL
            )
            "Режим 'Не беспокоить': ${if (enable) "ВКЛ" else "ВЫКЛ"}"
        } else {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Открыты настройки доступа к режиму 'Не беспокоить'"
        }
    }

    fun setFlashlight(enable: Boolean): String {
        return try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cm.cameraIdList.firstOrNull() ?: return "Камера со вспышкой не найдена"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.setTorchMode(cameraId, enable)
            }
            "Фонарик ${if (enable) "включён" else "выключен"}"
        } catch (e: Exception) {
            "Ошибка фонарика: ${e.message}"
        }
    }

    fun vibrateDevice(durationMs: Long): String {
        val vib = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        if (vib != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vib.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(durationMs)
            }
        }
        return "Вибрация $durationMs мс"
    }

    fun openBatterySaverSettings(): String {
        val intent = Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыты настройки энергосбережения"
    }

    fun openCamera(mode: String): String {
        val action = if (mode.equals("video", ignoreCase = true)) {
            MediaStore.INTENT_ACTION_VIDEO_CAMERA
        } else {
            MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA
        }
        val intent = Intent(action).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыта камера ($mode)"
    }

    fun recordAudioShort(seconds: Int): String {
        return try {
            val outFile = File(context.externalCacheDir ?: context.filesDir, "voice_${System.currentTimeMillis()}.m4a")
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setOutputFile(outFile.absolutePath)
            recorder.prepare()
            recorder.start()
            Thread {
                try {
                    Thread.sleep(seconds.coerceIn(1, 60) * 1000L)
                    recorder.stop()
                } catch (_: Exception) {
                } finally {
                    recorder.release()
                }
            }.start()
            "Запись звука ($seconds сек.) в ${outFile.name}"
        } catch (e: Exception) {
            "Ошибка записи звука: ${e.message}"
        }
    }

    fun openGallery(): String {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            type = "image/*"
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыта Галерея"
    }

    fun dispatchMediaKey(state: String): String {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val keyCode = when (state.lowercase()) {
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous", "prev" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        return "Команда медиа-плееру: $state"
    }

    fun openMusicSearch(query: String, app: String): String {
        val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
            putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
            putExtra("query", query)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            "Запущен поиск трека '$query'"
        } catch (_: Exception) {
            openApplication(
                if (app.contains("youtube", true)) "com.google.android.apps.youtube.music" else "com.spotify.music",
                app
            )
            "Открыто музыкальное приложение ($app)"
        }
    }

    fun getNetworkStatus(): String {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork ?: return "Интернет отключён"
        val caps = cm.getNetworkCapabilities(net) ?: return "Нет активного соединения"
        val type = when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Мобильные данные"
            else -> "Подключено"
        }
        return "Интернет активен ($type)"
    }

    fun getBatteryStatus(): String {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val statusIntent = context.registerReceiver(null, filter)
        val status = statusIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        return "Заряд батареи: $pct% (${if (charging) "Заряжается" else "От батареи"})"
    }

    fun getLastKnownLocation(): String {
        return try {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            if (loc != null) {
                "Координаты: ${loc.latitude}, ${loc.longitude}"
            } else {
                "Координаты ещё не определены (включите GPS)"
            }
        } catch (e: Exception) {
            "Нет разрешения на геолокацию: ${e.message}"
        }
    }

    fun openGeoMap(address: String): String {
        val uri = Uri.parse("geo:0,0?q=${Uri.encode(address)}")
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыта карта: $address"
    }

    fun listLaunchableApps(): String {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val list = pm.queryIntentActivities(intent, 0)
            .take(40)
            .joinToString("\n") { "${it.loadLabel(pm)} (${it.activityInfo.packageName})" }
        return list
    }

    fun openPlayStoreMarket(packageName: String): String {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыта страница $packageName в Google Play"
    }

    fun requestUninstallPackage(packageName: String): String {
        val intent = Intent(Intent.ACTION_DELETE, Uri.parse("package:$packageName")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "Открыт диалог удаления $packageName"
    }

    fun enqueueDownload(url: String, fileName: String): String {
        return try {
            val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val req = DownloadManager.Request(Uri.parse(url))
                .setTitle(fileName)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
            dm.enqueue(req)
            "Файл '$fileName' поставлен в загрузку"
        } catch (e: Exception) {
            "Ошибка DownloadManager: ${e.message}"
        }
    }

    fun openMessengerDeepLink(app: String, phone: String, text: String): String {
        val cleanPhone = phone.replace(Regex("[^0-9+]"), "")
        val uri = when (app.lowercase()) {
            "whatsapp" -> Uri.parse("whatsapp://send?phone=$cleanPhone&text=${Uri.encode(text)}")
            else -> Uri.parse("tg://resolve?phone=${cleanPhone.removePrefix("+")}")
        }
        return try {
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            "Открыт чат в $app ($phone)"
        } catch (_: Exception) {
            "Приложение $app не установлено"
        }
    }

    fun scheduleAlarmGoal(goal: String, delaySeconds: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("scheduled_goal", goal)
        }
        val pi = PendingIntent.getActivity(
            context,
            7901,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val triggerAt = SystemClock.elapsedRealtime() + delaySeconds * 1000L
        am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
    }

    fun schedulePeriodicGoal(goal: String, intervalSeconds: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("scheduled_goal", goal)
        }
        val pi = PendingIntent.getActivity(
            context,
            7902,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val intervalMs = intervalSeconds.coerceAtLeast(60) * 1000L
        am.setInexactRepeating(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + intervalMs,
            intervalMs,
            pi
        )
    }

    fun cancelScheduledGoals() {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (code in listOf(7901, 7902)) {
            val intent = Intent(context, MainActivity::class.java)
            val pi = PendingIntent.getActivity(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pi)
        }
    }
}
