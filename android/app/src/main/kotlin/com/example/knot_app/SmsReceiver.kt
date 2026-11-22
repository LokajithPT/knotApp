package com.example.knot_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.telephony.SmsMessage
import io.flutter.plugin.common.MethodChannel

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "android.provider.Telephony.SMS_RECEIVED") return

        val bundle: Bundle? = intent.extras
        if (bundle == null) return

        val pdus: Array<*>? = bundle["pdus"] as? Array<*>
        if (pdus == null) return

        for (pdu in pdus) {
            try {
                val sms = SmsMessage.createFromPdu(pdu as ByteArray)
                val sender = sms.originatingAddress ?: "Unknown"
                val body = sms.messageBody ?: ""

                // Send to Dart via MethodChannel (if engine is running)
                MainActivity.smsChannel.invokeMethod("onSmsReceived", mapOf(
                    "sender" to sender,
                    "body" to body,
                    "timestamp" to System.currentTimeMillis()
                ))
            } catch (e: Exception) {
                // Silently ignore malformed SMS
            }
        }
    }
}
