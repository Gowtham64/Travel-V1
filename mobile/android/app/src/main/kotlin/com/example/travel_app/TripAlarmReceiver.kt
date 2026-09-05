package com.example.travel_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class TripAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val REMINDER_CHANNEL_ID = "voyplan_trip_reminders"
        const val REMINDER_BASE_NOTIF_ID = 2000
    }

    override fun onReceive(context: Context, intent: Intent) {
        val idStr = intent.getStringExtra("id") ?: "reminder_${System.currentTimeMillis()}"
        val tripId = intent.getStringExtra("tripId") ?: idStr
        val title = intent.getStringExtra("title") ?: "🚗 Your trip is ready to start!"
        val body = intent.getStringExtra("body") ?: "Time to start your journey. Tap to begin navigation."
        val destination = intent.getStringExtra("destination") ?: "Trip"
        val actionType = intent.getStringExtra("actionType") ?: "trip_start"
        val departureTime = intent.getStringExtra("departureTime") ?: ""

        ensureChannel(context)

        val nid = REMINDER_BASE_NOTIF_ID + Math.abs(idStr.hashCode() % 1000)

        // Tapping the notification opens MainActivity and directs to Trip Confirmation popup
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("tripId", tripId)
            putExtra("action", actionType)
            putExtra("destination", destination)
            putExtra("departureTime", departureTime)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            nid,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, REMINDER_CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setSubText(destination)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)

        try {
            NotificationManagerCompat.from(context).notify(nid, builder.build())
        } catch (_: SecurityException) {
            // Permission not granted
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(NotificationManager::class.java)
            if (mgr != null && mgr.getNotificationChannel(REMINDER_CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    REMINDER_CHANNEL_ID,
                    "Trip Reminders & Start Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Trip departure alerts and trip start notifications"
                    setShowBadge(true)
                    enableVibration(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                }
                mgr.createNotificationChannel(channel)
            }
        }
    }
}
