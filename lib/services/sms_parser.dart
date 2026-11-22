import 'dart:convert';
import '../models/transaction.dart';

/// Result of parsing a financial SMS.
class SmsParseResult {
  final double amount;
  final String type; // 'debit' | 'credit'
  final String merchant;
  final String? accountMask;
  final String? upiRef;
  final String? upiId;
  final double? balance;
  final DateTime? date;
  final String? bank;
  final double confidence; // 0.0 - 1.0
  final List<String> signals;

  SmsParseResult({
    required this.amount,
    required this.type,
    required this.merchant,
    this.accountMask,
    this.upiRef,
    this.upiId,
    this.balance,
    this.date,
    this.bank,
    this.confidence = 0.0,
    this.signals = const [],
  });
}

class SmsParser {
  // -------- regexes --------

  static final _currency = RegExp(
    r'(?:INR|Rs\.?|₹)\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static final _balanceLabel = RegExp(
    r'(?:avl\s*bal|available\s*bal|balance|bal)\b',
    caseSensitive: false,
  );

  static final _upiRef = RegExp(
    r'(?:upi(?:\s*(?:ref|ref no|ref id|transaction|id|txn))?\s*:?\s*|ref\s*(?:no|id|number)?\s*:?\s*|txn\s*(?:id|number)?\s*:?\s*|utr\s*:?\s*)'
    r'(\d{6,})',
    caseSensitive: false,
  );

  static final _upiId = RegExp(
    r'\b([a-zA-Z0-9._-]{2,40}@[a-zA-Z]{2,20})\b',
  );

  static final _accountMask = RegExp(
    r'(?:acct|a/c|account|card|ending with)\s*(?:with\s+of\s+)?([Xx\d]{4,}[Xx\d]*)',
    caseSensitive: false,
  );

  // bare masked accounts like XXX377 or 1234XXXX
  static final _bareMask = RegExp(r'\b([Xx]{2,}\d{2,}|\d{2,}[Xx]{2,})\b');

  static final _dateDmy = RegExp(
    r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b',
  );

  static final _dateMon = RegExp(
    r'\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*(\d{2,4})\b',
    caseSensitive: false,
  );

  static final _bankName = RegExp(
    r'(?:-|\b)(canara|hdfc|icici|sbi|axis|kotak|idbi|pnb|union|boi|baroda|indusind|federal|rbl|yesbank|idfc|standard chartered|hsbc|citibank|au small|equitas|bandhan|dcb|karnataka|karur|tamilnad|indian|overseas|central|uco|bank of|state bank)\b',
    caseSensitive: false,
  );

  // tokens that are clearly not merchants
  static final _merchantStopWords = RegExp(
    r'\b(not you|blockupi|sms|to|upi|bal|inr|rs|on|at|via|acct|account|dr|cr|debited|credited|your|dear|customer|ref|txn|id|no|number)\b',
    caseSensitive: false,
  );

  // -------- entry point --------

  static Transaction? parse(String sender, String body) {
    final result = _tryParse(body);
    if (result == null) return null;
    if (result.confidence < 0.35) return null;

    final id = _stableId(result, sender);
    final date = result.date ?? DateTime.now();

    return Transaction(
      id: id,
      amount: result.amount,
      type: result.type,
      merchant: result.merchant,
      accountMask: result.accountMask,
      upiRef: result.upiRef,
      upiId: result.upiId,
      balance: result.balance,
      date: date,
      sender: sender,
      rawBody: body,
      source: 'sms',
      confidence: result.confidence,
      bank: result.bank,
    );
  }

  static SmsParseResult? _tryParse(String body) {
    final lower = body.toLowerCase();

    // Reject pure OTP / non-financial messages unless they carry money keywords.
    if (_isOtpOnly(lower)) return null;

    // ---- Type ----
    String? type;
    double typeScore = 0.0;
    final drMatch = RegExp(r'\b(?:acct\s+x*\d+\s+)?dr\.?\b', caseSensitive: false).firstMatch(body);
    final crMatch = RegExp(r'\b(?:acct\s+x*\d+\s+)?cr\.?\b', caseSensitive: false).firstMatch(body);
    final debited = RegExp(r'\bdebited\b', caseSensitive: false).firstMatch(body);
    final credited = RegExp(r'\bcredited\b', caseSensitive: false).firstMatch(body);

    if (drMatch != null || debited != null) {
      type = 'debit';
      typeScore = (drMatch != null) ? 0.9 : 0.7;
    } else if (crMatch != null || credited != null) {
      type = 'credit';
      typeScore = (crMatch != null) ? 0.9 : 0.7;
    } else if (RegExp(r'\b(paid|spent|withdraw|withdrawal|debited from)\b', caseSensitive: false).hasMatch(body)) {
      type = 'debit';
      typeScore = 0.5;
    } else if (RegExp(r'\b(received|refund|cashback|credited to|money received)\b', caseSensitive: false).hasMatch(body)) {
      type = 'credit';
      typeScore = 0.5;
    }
    if (type == null) return null;

    // ---- Amounts ----
    final amounts = <_AmountMatch>[];
    for (final m in _currency.allMatches(body)) {
      final raw = m.group(1)!;
      final value = double.tryParse(raw.replaceAll(',', ''));
      if (value == null) continue;
      final start = m.start;
      final preceding = body.substring(0, start).replaceAll(RegExp(r'\s+'), ' ');
      final isBalance = _balanceLabel.hasMatch(preceding.length > 40
          ? preceding.substring(preceding.length - 40)
          : preceding);
      amounts.add(_AmountMatch(value: value, start: start, isBalance: isBalance));
    }
    if (amounts.isEmpty) return null;

    // Transaction amount = non-balance amount closest to type indicator;
    // else first non-balance; else first amount.
    int typeIdx = -1;
    final typeRegex = (type == 'debit')
        ? RegExp(r'\bdr\.?\b|\bdebited\b', caseSensitive: false)
        : RegExp(r'\bcr\.?\b|\bcredited\b', caseSensitive: false);
    final typeM = typeRegex.firstMatch(body);
    if (typeM != null) typeIdx = typeM.start;

    double amount;
    int amountIdx = -1;
    final nonBalance = amounts.where((a) => !a.isBalance).toList();
    final candidates = nonBalance.isNotEmpty ? nonBalance : amounts;
    if (typeIdx >= 0) {
      candidates.sort((a, b) => (a.start - typeIdx).abs().compareTo((b.start - typeIdx).abs()));
    }
    final chosen = candidates.first;
    amount = chosen.value;
    amountIdx = chosen.start;

    // ---- Merchant ----
    String merchant = 'Unknown';
    double merchScore = 0.0;

    // to X;
    final toSemi = RegExp(r'\bto\s+([^;]{2,40}?)\s*;', caseSensitive: false).firstMatch(body);
    if (toSemi != null) {
      merchant = _cleanMerchant(toSemi.group(1)!);
      merchScore = 0.85;
    }
    if (merchScore < 0.8) {
      final toAlt = RegExp(r'\bto\s+([A-Za-z0-9 .&\x27-]{2,40}?)(?:\s*;|\s+upi|\s+bal|\s+inr|\s+on|\s+not|\s*$)', caseSensitive: false).firstMatch(body);
      if (toAlt != null) {
        final m = _cleanMerchant(toAlt.group(1)!);
        if (m.isNotEmpty && m != 'Unknown') { merchant = m; merchScore = 0.75; }
      }
    }
    if (merchScore < 0.7) {
      final atMatch = RegExp(r'\bat\s+([A-Za-z0-9 .&\x27-]{2,40}?)(?:\s*;|\s+upi|\s+bal|\s+inr|\s+on|\s+not|\s*$)', caseSensitive: false).firstMatch(body);
      if (atMatch != null) {
        final m = _cleanMerchant(atMatch.group(1)!);
        if (m.isNotEmpty && m != 'Unknown') { merchant = m; merchScore = 0.7; }
      }
    }
    if (merchScore < 0.65) {
      final viaMatch = RegExp(r'\bvia\s+([A-Za-z0-9 .&\x27-]{2,40}?)(?:\s*;|\s+upi|\s+bal|\s+inr|\s+on|\s+not|\s*$)', caseSensitive: false).firstMatch(body);
      if (viaMatch != null) {
        final m = _cleanMerchant(viaMatch.group(1)!);
        if (m.isNotEmpty && m != 'Unknown') { merchant = m; merchScore = 0.65; }
      }
    }
    // Fallback: nearest capitalized token sequence to the amount
    if (merchScore < 0.5) {
      final fallback = _merchantFallback(body, amountIdx);
      if (fallback != null) { merchant = fallback; merchScore = 0.4; }
    }

    // ---- UPI ref ----
    String? upiRef;
    final upiRefM = _upiRef.firstMatch(body);
    if (upiRefM != null) upiRef = upiRefM.group(1);

    // ---- UPI id ----
    String? upiId;
    final upiIdM = _upiId.firstMatch(body);
    if (upiIdM != null) upiId = upiIdM.group(1);

    // ---- Account mask ----
    String? accountMask;
    final acctM = _accountMask.firstMatch(body);
    if (acctM != null) accountMask = acctM.group(1)!.toUpperCase();
    else {
      final bare = _bareMask.firstMatch(body);
      if (bare != null) accountMask = bare.group(1)!.toUpperCase();
    }

    // ---- Balance ----
    double? balance;
    final balM = RegExp(r'(?:avl\s*bal|available\s*bal|balance|bal)\s*(?:inr|rs\.?|₹)?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)', caseSensitive: false).firstMatch(body);
    if (balM != null) {
      balance = double.tryParse(balM.group(1)!.replaceAll(',', ''));
    }

    // ---- Date ----
    DateTime? date;
    final dmy = _dateDmy.firstMatch(body);
    if (dmy != null) {
      date = _parseDmy(dmy.group(1)!, dmy.group(2)!, dmy.group(3)!);
    } else {
      final mon = _dateMon.firstMatch(body);
      if (mon != null) {
        date = _parseMon(mon.group(1)!, mon.group(2)!, mon.group(3)!);
      }
    }

    // ---- Bank ----
    String? bank;
    final bankM = _bankName.firstMatch(body);
    if (bankM != null) bank = bankM.group(1)!;

    // ---- Confidence ----
    double confidence = 0.0;
    confidence += typeScore * 0.25;
    confidence += 0.25; // amount present
    confidence += merchScore * 0.20;
    if (upiRef != null) confidence += 0.10;
    if (upiId != null) confidence += 0.05;
    if (balance != null) confidence += 0.05;
    if (date != null) confidence += 0.05;
    if (accountMask != null) confidence += 0.03;
    if (bank != null) confidence += 0.02;
    confidence = confidence.clamp(0.0, 1.0);

    final signals = <String>[];
    if (typeScore >= 0.7) signals.add('explicit-$type');
    if (upiRef != null) signals.add('upi-ref');
    if (upiId != null) signals.add('upi-id');
    if (balance != null) signals.add('balance');
    if (date != null) signals.add('date');

    return SmsParseResult(
      amount: amount,
      type: type,
      merchant: merchant,
      accountMask: accountMask,
      upiRef: upiRef,
      upiId: upiId,
      balance: balance,
      date: date,
      bank: bank,
      confidence: confidence,
      signals: signals,
    );
  }

  static String _cleanMerchant(String s) {
    var m = s.trim();
    // strip trailing reference-ish / label tokens
    m = m.replaceAll(RegExp(r'\s+(upi|ref|txn|id|no|number|inr|bal|balance)\b.*$', caseSensitive: false), '');
    m = m.replaceAll(RegExp(r'\s+\d{6,}\s*$'), ''); // trailing long number
    m = m.replaceAll(RegExp(r'[;:,\-]\s*$'), '').trim();
    // collapse internal whitespace
    m = m.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (m.isEmpty) return 'Unknown';
    // capitalize words nicely
    return m.split(' ').map((w) {
      if (w.isEmpty) return w;
      if (w == w.toUpperCase() && w.length > 1) return w; // keep acronyms
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  static String? _merchantFallback(String body, int amountIdx) {
    // Take a window around the amount and grab the first sensible capitalized phrase.
    final start = (amountIdx - 60).clamp(0, body.length);
    final end = (amountIdx + 60).clamp(0, body.length);
    final window = body.substring(start, end);
    final cap = RegExp(r'[A-Z][A-Za-z0-9 .&\x27-]{2,30}').allMatches(window);
    for (final m in cap) {
      final w = m.group(0)!;
      if (!_merchantStopWords.hasMatch(w)) return w.trim();
    }
    return null;
  }

  static bool _isOtpOnly(String lower) {
    final hasMoney = RegExp(r'(inr|rs\.?|₹|\bdr\.?\b|\bcr\.?\b|debited|credited|balance|upi)').hasMatch(lower);
    final isOtp = lower.contains('otp') || RegExp(r'\botp\b').hasMatch(lower);
    return isOtp && !hasMoney;
  }

  static DateTime _parseDmy(String d, String m, String y) {
    final day = int.tryParse(d) ?? 1;
    final month = int.tryParse(m) ?? 1;
    var year = int.tryParse(y) ?? DateTime.now().year;
    if (year < 100) year += 2000;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return DateTime.now();
    }
  }

  static DateTime _parseMon(String d, String mon, String y) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final day = int.tryParse(d) ?? 1;
    final month = months[mon.toLowerCase()] ?? 1;
    var year = int.tryParse(y) ?? DateTime.now().year;
    if (year < 100) year += 2000;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Deterministic, stable id across app restarts (not Dart hashCode).
  static String _stableId(SmsParseResult r, String sender) {
    if (r.upiRef != null && r.upiRef!.isNotEmpty) return 'upi_${r.upiRef}';
    if (r.upiId != null && r.upiId!.isNotEmpty) return 'upiid_${r.upiId}';
    final key = '${r.amount}|${r.type}|${_norm(r.merchant)}|${_norm(r.accountMask ?? '')}|${_norm(r.upiId ?? '')}|${r.date?.millisecondsSinceEpoch ?? 0}|${_norm(sender)}';
    return 'tx_${_base64Url(key)}';
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');

  static String _base64Url(String s) {
    final bytes = utf8.encode(s);
    return base64Url.encode(bytes).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }
}

class _AmountMatch {
  final double value;
  final int start;
  final bool isBalance;
  _AmountMatch({required this.value, required this.start, required this.isBalance});
}
