package com.pulseagent.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

class AgentForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "pulse_agent_progress_channel"
        private const val NOTIF_ID = 9101

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Статус задач PulseAgent",
                    NotificationManager.IMPORTANCE_LOW
                )
                nm.createNotificationChannel(channel)
            }
        }

        @Suppress("DEPRECATION")
        private fun newBuilder(context: Context): Notification.Builder {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                Notification.Builder(context)
            }
        }

        fun updateStatusNotification(
            context: Context,
            title: String,
            body: String,
            step: Int,
            maxSteps: Int,
            ongoing: Boolean
        ) {
            ensureChannel(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val openIntent = Intent(context, MainActivity::class.java)
            val pi = PendingIntent.getActivity(
                context,
                0,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notif = newBuilder(context)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setProgress(maxSteps.coerceAtLeast(1), step.coerceIn(0, maxSteps), false)
                .setOngoing(ongoing)
                .setOnlyAlertOnce(true)
                .setContentIntent(pi)
                .build()
            nm.notify(NOTIF_ID, notif)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel(applicationContext)
        val notif: Notification = newBuilder(applicationContext)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("PulseAgent активен")
            .setContentText("Ожидание команд пользователя")
            .setOngoing(true)
            .build()
        try {
            startForeground(NOTIF_ID, notif)
        } catch (_: Exception) {}
        return START_STICKY
    }
}
