package com.wizano.shop_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
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
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.wizano.shop_app/notifications"
    private val speechChannelName = "com.wizano.shop_app/system_speech"
    private val speechEventsName = "com.wizano.shop_app/system_speech_events"
    private val messagesChannelId = "wizano_messages_v2"
    private val legacyMessagesChannelId = "wizano_messages"
    private val permissionRequestCode = 4102
    private val conversationExtra = "wizano.conversation_id"
    private val senderExtra = "wizano.conversation_name"

    private var speechRecognizer: SpeechRecognizer? = null
    private var speechEvents: EventChannel.EventSink? = null
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
                    val conversationId = call.argument<String>("conversationId") ?: "general"
                    val senderName = call.argument<String>("senderName") ?: "عميل"
                    val body = call.argument<String>("body") ?: "أرسل لك رسالة جديدة"
                    val count = call.argument<Int>("count") ?: 1
                    val shopId = call.argument<String>("shopId")
                    val timestamp = call.argument<Number>("timestampMs")?.toLong()
                        ?: System.currentTimeMillis()
                    showMessageNotification(conversationId, senderName, body, count, timestamp, shopId)
                    result.success(null)
                }
                // يحفظ جلسة الرد المباشر (رمز الوصول ورابط الخادم) ليتمكن
                // ReplyReceiver من إرسال الرد دون فتح التطبيق.
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
                // يستهلكه التطبيق عند الإقلاع أو العودة من الخلفية.
                "consumeTarget" -> {
                    val target = pendingTarget
                    pendingTarget = null
                    result.success(target)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, speechEventsName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    speechEvents = events
                }
                override fun onCancel(arguments: Any?) {
                    speechEvents = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, speechChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(SpeechRecognizer.isRecognitionAvailable(this))
                    "start" -> {
                        val locale = call.argument<String>("locale") ?: "ar-YE"
                        startSystemRecognition(locale)
                        result.success(null)
                    }
                    "stop" -> {
                        speechRecognizer?.stopListening()
                        result.success(null)
                    }
                    "cancel" -> {
                        speechRecognizer?.cancel()
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

    /**
     * إشعار مفتوح -> نستخرج المحادثة المطلوبة ونمرّرها لدارت.
     * إن كان المحرك جاهزًا نرسلها فورًا، وإلا نحتفظ بها حتى يطلبها التطبيق.
     */
    private fun consumeNotificationIntent(intent: Intent?) {
        val conversationId = intent?.getStringExtra(conversationExtra) ?: return
        val senderName = intent.getStringExtra(senderExtra).orEmpty()
        intent.removeExtra(conversationExtra)
        intent.removeExtra(senderExtra)
        val target = mapOf(
            "type" to "message",
            "conversationId" to conversationId,
            "senderName" to senderName,
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

    private fun startSystemRecognition(locale: String) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            sendSpeechEvent("error", message = "خدمة التعرف على الكلام غير متاحة في هذا الهاتف")
            return
        }
        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
                override fun onPartialResults(partialResults: Bundle?) {
                    sendSpeechEvent("partial", bestSpeech(partialResults))
                }
                override fun onResults(results: Bundle?) {
                    sendSpeechEvent("final", bestSpeech(results))
                }
                override fun onError(error: Int) {
                    val message = when (error) {
                        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "تعذر الاتصال بخدمة التعرف"
                        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "لم أسمع كلامًا واضحًا"
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "لا يوجد إذن للميكروفون"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "خدمة التعرف مشغولة، أعد المحاولة"
                        else -> "تعذر التعرف على الكلام"
                    }
                    sendSpeechEvent("error", message = message)
                }
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            }
            startListening(intent)
        }
    }

    private fun bestSpeech(bundle: Bundle?): String {
        return bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()?.trim().orEmpty()
    }

    private fun sendSpeechEvent(type: String, text: String = "", message: String = "") {
        runOnUiThread {
            speechEvents?.success(mapOf("type" to type, "text" to text, "message" to message))
        }
    }

    override fun onDestroy() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        notificationsChannel = null
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        // القناة القديمة بلا صوت/اهتزاز مضبوطين؛ نستبدلها بقناة جديدة لأن
        // أندرويد لا يسمح بتغيير أهمية القناة بعد إنشائها.
        manager.deleteNotificationChannel(legacyMessagesChannelId)
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val channel = NotificationChannel(
            messagesChannelId,
            "رسائل العملاء",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "رسائل العملاء الجديدة، مع نص الرسالة وفتح المحادثة مباشرة"
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
        ) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequestCode)
        }
    }

    private fun canPostNotifications(): Boolean {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        return granted && NotificationManagerCompat.from(this).areNotificationsEnabled()
    }

    /**
     * إشعار بنمط المحادثات (MessagingStyle) كما في واتساب: اسم العميل،
     * نص رسالته، الوقت، والضغط ينقل مباشرة إلى المحادثة نفسها.
     */
    private fun showMessageNotification(
        conversationId: String,
        senderName: String,
        body: String,
        count: Int,
        timestampMs: Long,
        shopId: String?,
    ) {
        if (!canPostNotifications()) return
        val me = Person.Builder().setName("أنا").build()
        val sender = Person.Builder()
            .setName(senderName)
            .setKey(conversationId)
            .apply { appLogo?.let { setIcon(IconCompat.createWithBitmap(it)) } }
            .build()
        val style = NotificationCompat.MessagingStyle(me)
            .setConversationTitle(senderName)
            .addMessage(body, timestampMs, sender)

        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = "com.wizano.shop_app.OPEN_CONVERSATION"
            putExtra(conversationExtra, conversationId)
            putExtra(senderExtra, senderName)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            conversationId.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // إشعار «محادثة» حقيقي (قسم المحادثات في أندرويد 11+) يحتاج اختصارًا
        // ديناميكيًا مرتبطًا بالشخص، وإلا ظهر الإشعار كتنبيه عادي بلا صورة.
        val shortcut = ShortcutInfoCompat.Builder(this, conversationId)
            .setShortLabel(senderName)
            .setLongLabel(senderName)
            .setIntent(openIntent)
            .apply { appLogo?.let { setIcon(IconCompat.createWithBitmap(it)) } }
            .build()
        ShortcutManagerCompat.pushDynamicShortcut(this, shortcut)

        // زر «رد» كما في واتساب: نص يُكتب داخل الإشعار ويُرسل مباشرة
        // عبر ReplyReceiver دون فتح التطبيق.
        val replyInput = RemoteInput.Builder(ReplyReceiver.KEY_REPLY_TEXT)
            .setLabel("اكتب ردك…")
            .build()
        val replyIntent = Intent(this, ReplyReceiver::class.java).apply {
            action = ReplyReceiver.ACTION_REPLY
            putExtra(ReplyReceiver.EXTRA_CONVERSATION, conversationId)
            putExtra(ReplyReceiver.EXTRA_SHOP, shopId)
            putExtra(ReplyReceiver.EXTRA_SENDER, senderName)
            putExtra(ReplyReceiver.EXTRA_NOTIFICATION_ID, conversationId.hashCode())
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            this,
            conversationId.hashCode() + 1,
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
            .setContentTitle(senderName)
            .setContentText(body)
            .setStyle(style)
            .setContentIntent(contentIntent)
            .setShortcutId(conversationId)
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

        NotificationManagerCompat.from(this).notify(conversationId.hashCode(), notification)
    }
}
