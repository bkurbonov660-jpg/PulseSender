package com.pulseagent.app

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationReaderService : NotificationListenerService() {
    companion object {
        var instance: NotificationReaderService? = null
        private val cachedNotifications = mutableMapOf<String, StatusBarNotification>()

        private val messengerPackages = setOf(
            "ru.oneme.app",
            "org.telegram.messenger",
            "org.telegram.messenger.web",
            "com.whatsapp",
            "com.vkontakte.android",
            "com.google.android.apps.messaging",
            "com.android.mms"
        )

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
                        sb.append("[${sbn.packageName}] $title: $text (key=${sbn.key})\n")
                    }
                }
                if (sb.isEmpty()) "Уведомлений с текстом нет" else sb.toString().trim()
            } catch (e: Exception) {
                "Ошибка чтения уведомлений: ${e.message}"
            }
        }

        fun replyInline(context: Context, key: String, replyText: String): Boolean {
            val sbn = cachedNotifications[key] ?: instance?.activeNotifications?.firstOrNull { it.key == key }
                ?: return false
            val actions = sbn.notification.actions ?: return false
            for (act in actions) {
                val remoteInputs = act.remoteInputs ?: continue
                if (remoteInputs.isNotEmpty() && act.actionIntent != null) {
                    val localIntent = Intent()
                    val bundle = Bundle()
                    for (ri in remoteInputs) {
                        bundle.putCharSequence(ri.resultKey, replyText)
                    }
                    RemoteInput.addResultsToIntent(remoteInputs, localIntent, bundle)
                    return try {
                        act.actionIntent.send(context, 0, localIntent)
                        true
                    } catch (_: Exception) {
                        false
                    }
                }
            }
            return false
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        cachedNotifications[sbn.key] = sbn

        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        if (title.isEmpty() || text.isEmpty()) return

        val hasReplyAction = sbn.notification.actions?.any {
            it.remoteInputs != null && it.remoteInputs.isNotEmpty()
        } ?: false

        if (messengerPackages.contains(pkg) || hasReplyAction) {
            MainActivity.notifyIncomingNotification(
                mapOf(
                    "package" to pkg,
                    "title" to title,
                    "text" to text,
                    "key" to sbn.key,
                    "canReply" to hasReplyAction
                )
            )
        }
    }

    override fun onListenerDisconnected() {
        if (instance == this) instance = null
        super.onListenerDisconnected()
    }
}
