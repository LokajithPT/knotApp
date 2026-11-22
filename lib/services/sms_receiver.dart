import 'dart:async';
import 'package:flutter/services.dart';
import '../models/transaction.dart';
import '../services/money_service.dart';
import 'transaction_note_service.dart';

/// Listens for incoming SMS from the native Android receiver via MethodChannel,
/// parses them into transactions, and ingests them automatically.
class SmsReceiverService {
  static const MethodChannel _channel = MethodChannel('knot_app/sms_receiver');
  static bool _listening = false;
  static final StreamController<Transaction> _txController =
      StreamController<Transaction>.broadcast();

  /// Stream of newly parsed transactions from incoming SMS.
  static Stream<Transaction> get onTransactionReceived => _txController.stream;

  /// Initialize the SMS receiver. Call this once at app startup.
  static Future<void> init() async {
    if (_listening) return;
    _listening = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSmsReceived') {
        final args = call.arguments as Map? ?? {};
        final sender = args['sender'] as String? ?? 'Unknown';
        final body = args['body'] as String? ?? '';

        try {
          final tx = await MoneyService.ingestSms(sender, body);
          if (tx != null) {
            _txController.add(tx);
            // Auto-write every parsed transaction to the Money note
            try {
              await TransactionNoteService.appendTransaction(tx);
            } catch (_) {
              // Never let a note-write failure break SMS ingestion
            }
            // If the transaction needs categorization, notify the UI
            if (tx.needsEmoji) {
              _notifyPendingTx(tx);
            }
          }
        } catch (e) {
          // Silently ignore parse errors for incoming SMS
        }
        return null;
      }
      return null;
    });
  }

  /// Dispose resources.
  static void dispose() {
    _listening = false;
    _txController.close();
  }

  static void _notifyPendingTx(Transaction tx) {
    // The money screen or home screen can listen to onTransactionReceived
    // and show the categorization UI. This is a lightweight broadcast.
  }
}
