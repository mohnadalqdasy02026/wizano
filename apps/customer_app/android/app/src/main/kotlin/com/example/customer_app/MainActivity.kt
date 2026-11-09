package com.wizano.customer_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.wizano.customer_app/notifications"
    private val messagesChannelId = "wizano_customer_messages_v2"
    private val legacyMessagesChannelId = "wizano_customer_messages"
    private val permissionRequestCode = 4202
    private val shopExtra = "wizano.shop_id"
    private val shopNameExtra = "wizano.shop_name"

    private var notificationsChannel: MethodChannel? = null

    /** وجهة لم تُسلَّم لدارت بعد (إقلاع بارد من إشعار). */
    private var pendingTarget: Map<String, String>? = null

    /** شعار وزانو كما يظهر داخل الإشعار (Large Icon + صورة المرسِل). */
    private val appLogo: Bitmap? by lazy {
        BitmapFactory.decodeResource(resources, R.drawable.ic_notification_logo)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        notificationsChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                "showMessage" -> {
                    val shopId = call.argument<String>("shopId") ?: "general"
                    val shopName = call.argument<String>("shopName") ?: "المحل"
                    val body = call.argument<String>("body") ?: "أرسل لك رسالة جديدة"
                    val count = call.argument<Int>("count") ?: 1
                    val timestamp = call.argument<Number>("timestampMs")?.toLong()
                        ?: System.currentTimeMillis()
                    showMessageNotification(shopId, shopName, body, count, timestamp)
                    result.success(null)
                }
                "consumeTarget" -> {
                    val target = pendingTarget
                    pendingTarget = null
                    result.success(target)
                }
                // جلسة الرد المباشر (رمز الوصول ورابط الخادم) لمستقبل الرد.
                "setReplySession" -> {
                    val apiBase = call.argument<String>("apiBase")
                    val accessToken = call.argument<String>("accessToken")
                    getSharedPreferences(ReplyReceiver.PREFS, Context.MODE_PRIVATE)
                        .edit()
                        .putString(ReplyReceiver.KEY_API_BASE, apiBase)
                        .putString(ReplyReceiver.KEY_TOKEN, accessToken)
                        .apply()
                    result.success(null)
                }
                "clearReplySession" -> {
                    getSharedPreferences(ReplyReceiver.PREFS, Context.MODE_PRIVATE)
                        .edit().clear().apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        consumeNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeNotificationIntent(intent)
    }

    private fun consumeNotificationIntent(intent: Intent?) {
        val shopId = intent?.getStringExtra(shopExtra) ?: return
        val shopName = intent.getStringExtra(shopNameExtra).orEmpty()
        intent.removeExtra(shopExtra)
        intent.removeExtra(shopNameExtra)
        val target = mapOf(
            "type" to "message",
            "shopId" to shopId,
            "shopName" to shopName,
        )
        pendingTarget = target
        runOnUiThread {
            notificationsChannel?.invokeMethod(
                "onNotificationTap",
                target,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        pendingTarget = null
                    }
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
                    override fun notImplemented() = Unit
                },
            )
        }
    }

    override fun onDestroy() {
        notificationsChannel = null
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.deleteNotificationChannel(legacyMessagesChannelId)
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val channel = NotificationChannel(
            messagesChannelId,
            "رسائل المحلات",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "رسائل جديدة من المحلات المرتبطة بحسابك، مع نص الرسالة"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 160, 110, 160)
            enableLights(true)
            lightColor = 0xFF14D7B0.toInt()
            setShowBadge(true)
            setSound(
                sound,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequestCode)
    }

    private fun canPostNotifications(): Boolean {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        return granted && NotificationManagerCompat.from(this).areNotificationsEnabled()
    }

    /** إشعار محادثة (MessagingStyle) بنص الرسالة، والضغط يفتح المحادثة. */
    private fun showMessageNotification(
        shopId: String,
        shopName: String,
        body: String,
        count: Int,
        timestampMs: Long,
    ) {
        if (!canPostNotifications()) return
        val me = Person.Builder().setName("أنا").build()
        val sender = Person.Builder()
            .setName(shopName)
            .setKey(shopId)
            .apply { appLogo?.let { setIcon(IconCompat.createWithBitmap(it)) } }
            .build()
        val style = NotificationCompat.MessagingStyle(me)
            .setConversationTitle(shopName)
            .addMessage(body, timestampMs, sender)

        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = "com.wizano.customer_app.OPEN_CONVERSATION"
            putExtra(shopExtra, shopId)
            putExtra(shopNameExtra, shopName)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            shopId.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // إشعار «محادثة» حقيقي (قسم المحادثات في أندرويد 11+) يحتاج اختصارًا
        // ديناميكيًا مرتبطًا بالشخص كي يظهر بصورة المرسِل.
        val shortcut = ShortcutInfoCompat.Builder(this, shopId)
            .setShortLabel(shopName)
            .setLongLabel(shopName)
            .setIntent(openIntent)
            .apply { appLogo?.let { setIcon(IconCompat.createWithBitmap(it)) } }
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(this, shortcut)

        // زر «رد» كما في واتساب: الرد يُرسل عبر ReplyReceiver دون فتح التطبيق.
        val replyInput = RemoteInput.Builder(ReplyReceiver.KEY_REPLY_TEXT)
            .setLabel("اكتب ردك…")
            .build()
        val replyIntent = Intent(this, ReplyReceiver::class.java).apply {
            action = ReplyReceiver.ACTION_REPLY
            putExtra(ReplyReceiver.EXTRA_SHOP, shopId)
            putExtra(ReplyReceiver.EXTRA_SENDER, shopName)
            putExtra(ReplyReceiver.EXTRA_NOTIFICATION_ID, shopId.hashCode())
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            this,
            shopId.hashCode() + 1,
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val replyAction = NotificationCompat.Action.Builder(
            R.drawable.ic_stat_wizano,
            "رد",
            replyPendingIntent,
        ).addRemoteInput(replyInput).build()

        val notification = NotificationCompat.Builder(this, messagesChannelId)
            .setSmallIcon(R.drawable.ic_stat_wizano)
            .setLargeIcon(appLogo)
            .setColor(0xFF14D7B0.toInt())
            .setContentTitle(shopName)
            .setContentText(body)
            .setStyle(style)
            .setContentIntent(contentIntent)
            .setShortcutId(shopId)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setNumber(count)
            .setWhen(timestampMs)
            .setShowWhen(true)
            .setSubText(if (count > 1) "$count رسائل جديدة" else null)
            .addAction(replyAction)
            .build()

        NotificationManagerCompat.from(this).notify(shopId.hashCode(), notification)
    }
}
