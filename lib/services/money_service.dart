import 'dart:io';
import 'dart:convert';
import '../models/transaction.dart';
import 'knot_service.dart';
import 'sms_parser.dart';
import 'emoji_service.dart';

class MoneyService {
  static String? _moneyDir;
  static Future<String> getMoneyDir() async {
    if (_moneyDir != null) return _moneyDir!;
    final knotDir = await KnotService.getKnotDir();
    _moneyDir = '$knotDir/_money';
    final dir = Directory(_moneyDir!);
    if (!await dir.exists()) await dir.create(recursive: true);
    return _moneyDir!;
  }

  static Future<String> _filePath() async {
    final dir = await getMoneyDir();
    return '$dir/transactions.json';
  }

  static Future<List<Transaction>> loadTransactions() async {
    final path = await _filePath();
    final file = File(path);
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final List decoded = jsonDecode(content);
      return decoded.map((e) => Transaction.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTransactions(List<Transaction> txs) async {
    final path = await _filePath();
    final file = File(path);
    await file.writeAsString(jsonEncode(txs.map((e) => e.toJson()).toList()));
  }

  /// Insert or update a transaction by stable id.
  /// Never wipes an existing emoji/category/reason unless the new value is explicitly set.
  static Future<void> upsertTransaction(Transaction tx) async {
    final txs = await loadTransactions();
    final idx = txs.indexWhere((t) => t.id == tx.id);
    if (idx >= 0) {
      final existing = txs[idx];
      txs[idx] = tx.copyWith(
        // preserve user-assigned emoji/category/reason if the incoming one is empty
        emoji: (tx.emoji == null || tx.emoji!.isEmpty) ? existing.emoji : tx.emoji,
        category: (tx.category == null || tx.category!.isEmpty) ? existing.category : tx.category,
        reason: (tx.reason == null || tx.reason!.isEmpty) ? existing.reason : tx.reason,
        isOrganized: tx.isOrganized ? true : existing.isOrganized,
        // keep the higher confidence parse
        confidence: tx.confidence > existing.confidence ? tx.confidence : existing.confidence,
      );
    } else {
      txs.insert(0, tx);
    }
    await saveTransactions(txs);
  }

  static Future<void> setEmoji(String id, String emoji, {String? reason, String? customCategory}) async {
    final custom = await EmojiService.loadCustom();
    final txs = await loadTransactions();
    final idx = txs.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      txs[idx].emoji = emoji;
      txs[idx].category = customCategory ?? EmojiCategory.categoryFor(emoji, custom: custom);
      txs[idx].isOrganized = true;
      if (reason != null && reason.trim().isNotEmpty) txs[idx].reason = reason.trim();
      await saveTransactions(txs);
    }
  }

  /// Update arbitrary fields on a transaction (used by edit screen).
  static Future<void> updateTransaction(String id, {
    double? amount, String? type, String? merchant, DateTime? date,
    String? emoji, String? category, String? reason, bool? isOrganized,
  }) async {
    final txs = await loadTransactions();
    final idx = txs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final t = txs[idx];
    txs[idx] = t.copyWith(
      amount: amount ?? t.amount,
      type: type ?? t.type,
      merchant: merchant ?? t.merchant,
      date: date ?? t.date,
      emoji: emoji ?? t.emoji,
      category: category ?? t.category,
      reason: reason ?? t.reason,
      isOrganized: isOrganized ?? t.isOrganized,
    );
    await saveTransactions(txs);
  }

  static Future<void> deleteTransaction(String id) async {
    final txs = await loadTransactions();
    txs.removeWhere((t) => t.id == id);
    await saveTransactions(txs);
  }

  static Future<List<Transaction>> getPending() async {
    final txs = await loadTransactions();
    return txs.where((t) => t.needsEmoji).toList();
  }

  static Future<Map<String, List<Transaction>>> groupedByEmoji() async {
    final txs = await loadTransactions();
    final map = <String, List<Transaction>>{};
    for (final t in txs) {
      final key = t.emoji ?? '❓';
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  /// Ingest an SMS: parse, auto-categorize, dedupe by stable id.
  static Future<Transaction?> ingestSms(String sender, String body) async {
    final tx = SmsParser.parse(sender, body);
    if (tx == null) return null;

    // Auto-categorize using merchant keywords so most SMS need no manual tagging.
    final custom = await EmojiService.loadCustom();
    final cat = EmojiCategory.categorizeMerchant(tx.merchant, custom: custom);
    if (cat != null) {
      tx.emoji = cat.key;
      tx.category = cat.value;
      tx.isOrganized = true;
    }

    await upsertTransaction(tx);
    return tx;
  }

  static Future<Map<String, double>> monthlySummary({DateTime? month}) async {
    final txs = await loadTransactions();
    final m = month ?? DateTime.now();
    final filtered = txs.where((t) => t.date.year == m.year && t.date.month == m.month).toList();
    double spent = filtered.where((t) => t.type == 'debit').fold(0, (a, b) => a + b.amount);
    double income = filtered.where((t) => t.type == 'credit').fold(0, (a, b) => a + b.amount);
    return {'spent': spent, 'income': income, 'count': filtered.length.toDouble()};
  }

  static Future<List<Transaction>> transactionsInMonth({DateTime? month}) async {
    final txs = await loadTransactions();
    final m = month ?? DateTime.now();
    return txs.where((t) => t.date.year == m.year && t.date.month == m.month).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }
}
