package com.wizano.shop_app

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * يستقبل الرد المكتوب في إشعار المحل (زر «رد» مثل واتساب) ويرسله إلى
 * الخادم مباشرة دون فتح التطبيق، ثم يزيل الإشعار.
 *
 * الجلسة (رمز الوصول ورابط الخادم) تُحفظ من التطبيق عبر
 * `setReplySession` في تفضيلات التطبيق الخاصة (غير مشفرة، لكنها داخل
 * صندوق التطبيق المحمي).
 */
class ReplyReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_REPLY = "com.wizano.shop_app.ACTION_REPLY"
        const val KEY_REPLY_TEXT = "wizano.reply_text"
        const val EXTRA_CONVERSATION = "wizano.reply_conversation"
        const val EXTRA_SHOP = "wizano.reply_shop"
        const val EXTRA_SENDER = "wizano.reply_sender"
        const val EXTRA_NOTIFICATION_ID = "wizano.reply_notification_id"
        const val PREFS = "wizano_reply"
        const val KEY_API_BASE = "api_base"
        const val KEY_TOKEN = "access_token"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_REPLY) return
        val text = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(KEY_REPLY_TEXT)?.toString()?.trim()
        if (text.isNullOrEmpty()) return
        val conversationId = intent.getStringExtra(EXTRA_CONVERSATION) ?: return
        val shopId = intent.getStringExtra(EXTRA_SHOP) ?: return
        val senderName = intent.getStringExtra(EXTRA_SENDER) ?: "عميل"
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val apiBase = prefs.getString(KEY_API_BASE, null)
        val token = prefs.getString(KEY_TOKEN, null)
        if (apiBase.isNullOrBlank() || token.isNullOrBlank()) {
            postFailure(context, senderName, "افتح التطبيق وسجّل الدخول ثم أعد المحاولة")
            return
        }

        val body = "{\"body\":\"${escapeJson(text)}\"}"
        val url = "$apiBase/api/v1/shops/$shopId/customers/$conversationId/messages"
        val nm = NotificationManagerCompat.from(context)
        nm.cancel(notificationId)

        thread {
            val ok = try {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.connectTimeout = 15000
                connection.readTimeout = 15000
                connection.setRequestProperty("content-type", "application/json")
                connection.setRequestProperty("authorization", "Bearer $token")
                connection.doOutput = true
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                connection.responseCode in 200..299
            } catch (_: Exception) {
                false
            }
            if (!ok) postFailure(context, senderName, "تعذر إرسال ردك — تحقق من اتصالك")
        }
    }

    private fun escapeJson(raw: String): String = buildString {
        for (ch in raw) {
            when (ch) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (ch.code < 0x20) append(" ") else append(ch)
            }
        }
    }

    private fun postFailure(context: Context, senderName: String, message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val openIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, "wizano_messages_v2")
            .setSmallIcon(R.drawable.ic_stat_wizano)
            .setContentTitle("لم يُرسل ردك إلى $senderName")
            .setContentText(message)
            .setContentIntent(openIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_ERROR)
            .build()
        NotificationManagerCompat.from(context).notify(9941, notification)
    }
}
