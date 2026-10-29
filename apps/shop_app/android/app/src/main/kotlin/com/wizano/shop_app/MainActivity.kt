package com.wizano.shop_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.wizano.shop_app/notifications"
    private val speechChannelName = "com.wizano.shop_app/system_speech"
    private val speechEventsName = "com.wizano.shop_app/system_speech_events"
    private val messagesChannelId = "wizano_messages"
    private val permissionRequestCode = 4102
    private var speechRecognizer: SpeechRecognizer? = null
    private var speechEvents: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }
                    "showMessage" -> {
                        val id = call.argument<Int>("id") ?: 1
                        val customerName = call.argument<String>("customerName") ?: "عميل"
                        val count = call.argument<Int>("count") ?: 1
                        showMessageNotification(id, customerName, count)
                        result.success(null)
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
            val intent = RecognizerIntent().apply {
                action = RecognizerIntent.ACTION_RECOGNIZE_SPEECH
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
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            messagesChannelId,
            "رسائل وزانو",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "تنبيهات الرسائل الجديدة بين المحل والعملاء"
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequestCode)
        }
    }

    private fun showMessageNotification(id: Int, customerName: String, count: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val text = if (count == 1) "لديك رسالة جديدة في وزانو" else "لديك $count رسائل جديدة في وزانو"
        val notification = NotificationCompat.Builder(this, messagesChannelId)
            .setSmallIcon(R.drawable.ic_launcher_wizano_shop)
            .setContentTitle("رسالة جديدة من $customerName")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSubText("WIZANO · الرسائل")
            .setNumber(count)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(this).notify(id, notification)
    }
}
