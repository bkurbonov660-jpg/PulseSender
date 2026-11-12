package com.pulseagent.app

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationReaderService : NotificationListenerService() {
    companion object {
        var instance: NotificationReaderService? = null

        fun dumpCurrentNotifications(): String {
            val svc = instance ?: return "Доступ к уведомлениям не включён в настройках"
            return try {
                val active: Array<StatusBarNotification> = svc.activeNotifications ?: emptyArray()
                if (active.isEmpty()) return "Активных уведомлений нет"
                val sb = StringBuilder()
                for (sbn in active.take(15)) {
                    val extras = sbn.notification.extras
                    val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
                    val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
                    if (title.isNotEmpty() || text.isNotEmpty()) {
                        sb.append("[${sbn.packageName}] $title: $text\n")
                    }
                }
                if (sb.isEmpty()) "Уведомлений с текстом нет" else sb.toString().trim()
            } catch (e: Exception) {
                "Ошибка чтения уведомлений: ${e.message}"
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onListenerDisconnected() {
        if (instance == this) instance = null
        super.onListenerDisconnected()
    }
}
