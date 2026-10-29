package com.wizano.shop_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.wizano.shop_app/notifications"
    private val messagesChannelId = "wizano_messages"
    private val permissionRequestCode = 4102

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
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(this).notify(id, notification)
    }
}
