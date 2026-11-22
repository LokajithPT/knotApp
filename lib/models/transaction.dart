
class Transaction {
  final String id;
  final double amount;
  final String type; // debit | credit
  final String merchant;
  final String? accountMask;     // e.g. XXX377
  final String? upiRef;          // numeric UPI reference
  final String? upiId;           // handle@bank UPI id
  final double? balance;         // account balance after txn
  final DateTime date;
  final String sender;           // SMS sender / source
  final String rawBody;          // original SMS / input (audit)
  String? emoji;
  String? category;
  bool isOrganized;
  String? reason;
  final String? bank;            // detected bank
  final String source;           // 'sms' | 'manual'
  final double confidence;       // 0.0 - 1.0 parse confidence

  Transaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.merchant,
    this.accountMask,
    this.upiRef,
    this.upiId,
    this.balance,
    required this.date,
    required this.sender,
    required this.rawBody,
    this.emoji,
    this.category,
    this.isOrganized = false,
    this.reason,
    this.bank,
    this.source = 'sms',
    this.confidence = 1.0,
  });

  bool get needsEmoji => emoji == null || emoji!.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'type': type,
        'merchant': merchant,
        'accountMask': accountMask,
        'upiRef': upiRef,
        'upiId': upiId,
        'balance': balance,
        'date': date.toIso8601String(),
        'sender': sender,
        'rawBody': rawBody,
        'emoji': emoji,
        'category': category,
        'isOrganized': isOrganized,
        'reason': reason,
        'bank': bank,
        'source': source,
        'confidence': confidence,
      };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'],
        amount: (j['amount'] as num).toDouble(),
        type: j['type'],
        merchant: j['merchant'],
        accountMask: j['accountMask'],
        upiRef: j['upiRef'],
        upiId: j['upiId'],
        balance: j['balance'] != null ? (j['balance'] as num).toDouble() : null,
        date: DateTime.parse(j['date']),
        sender: j['sender'],
        rawBody: j['rawBody'],
        emoji: j['emoji'],
        category: j['category'],
        isOrganized: j['isOrganized'] ?? false,
        reason: j['reason'],
        bank: j['bank'],
        source: j['source'] ?? 'sms',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 1.0,
      );

  Transaction copyWith({
    String? id,
    double? amount,
    String? type,
    String? merchant,
    String? accountMask,
    String? upiRef,
    String? upiId,
    double? balance,
    DateTime? date,
    String? sender,
    String? rawBody,
    String? emoji,
    String? category,
    bool? isOrganized,
    String? reason,
    String? bank,
    String? source,
    double? confidence,
  }) => Transaction(
        id: id ?? this.id,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        merchant: merchant ?? this.merchant,
        accountMask: accountMask ?? this.accountMask,
        upiRef: upiRef ?? this.upiRef,
        upiId: upiId ?? this.upiId,
        balance: balance ?? this.balance,
        date: date ?? this.date,
        sender: sender ?? this.sender,
        rawBody: rawBody ?? this.rawBody,
        emoji: emoji ?? this.emoji,
        category: category ?? this.category,
        isOrganized: isOrganized ?? this.isOrganized,
        reason: reason ?? this.reason,
        bank: bank ?? this.bank,
        source: source ?? this.source,
        confidence: confidence ?? this.confidence,
      );

  /// Human readable one-line summary.
  String get summary {
    final sign = type == 'credit' ? '+' : '-';
    return '$sign ₹${amount.toStringAsFixed(2)} • $merchant${upiRef != null ? ' (UPI $upiRef)' : ''}';
  }
}

class EmojiCategory {
  static const Map<String, String> categories = {
    '🍔': 'food',
    '🛒': 'groceries',
    '🚕': 'travel',
    '⛽': 'fuel',
    '💡': 'bills',
    '🎬': 'entertainment',
    '💊': 'health',
    '📚': 'education',
    '🛍️': 'shopping',
    '🏠': 'rent',
    '💸': 'transfer',
    '❓': 'other',
  };

  /// Merchant keywords -> (emoji, category). Used for auto-categorization.
  /// Order matters: more specific brands first.
  static const List<MapEntry<String, MapEntry<String, String>>> merchantRules = [
    // Food
    MapEntry('swiggy', MapEntry('🍔', 'food')),
    MapEntry('zomato', MapEntry('🍔', 'food')),
    MapEntry('dominos', MapEntry('🍔', 'food')),
    MapEntry('pizza', MapEntry('🍔', 'food')),
    MapEntry('burger', MapEntry('🍔', 'food')),
    MapEntry('mcdonald', MapEntry('🍔', 'food')),
    MapEntry('kfc', MapEntry('🍔', 'food')),
    MapEntry('foods', MapEntry('🍔', 'food')),
    MapEntry('restaurant', MapEntry('🍔', 'food')),
    MapEntry('cafe', MapEntry('🍔', 'food')),
    MapEntry('starbucks', MapEntry('🍔', 'food')),
    MapEntry('barista', MapEntry('🍔', 'food')),
    MapEntry('biryani', MapEntry('🍔', 'food')),
    MapEntry('mess', MapEntry('🍔', 'food')),
    MapEntry('canteen', MapEntry('🍔', 'food')),
    // Groceries
    MapEntry('bigbasket', MapEntry('🛒', 'groceries')),
    MapEntry('blinkit', MapEntry('🛒', 'groceries')),
    MapEntry('zepto', MapEntry('🛒', 'groceries')),
    MapEntry('dunzo', MapEntry('🛒', 'groceries')),
    MapEntry('grocery', MapEntry('🛒', 'groceries')),
    MapEntry('supermarket', MapEntry('🛒', 'groceries')),
    MapEntry('hypercity', MapEntry('🛒', 'groceries')),
    MapEntry('reliance', MapEntry('🛒', 'groceries')),
    MapEntry('more', MapEntry('🛒', 'groceries')),
    // Travel / Fuel
    MapEntry('uber', MapEntry('🚕', 'travel')),
    MapEntry('ola', MapEntry('🚕', 'travel')),
    MapEntry('rapido', MapEntry('🚕', 'travel')),
    MapEntry('irctc', MapEntry('🚕', 'travel')),
    MapEntry('makemytrip', MapEntry('🚕', 'travel')),
    MapEntry('goibibo', MapEntry('🚕', 'travel')),
    MapEntry('indigo', MapEntry('🚕', 'travel')),
    MapEntry('airindia', MapEntry('🚕', 'travel')),
    MapEntry('spicejet', MapEntry('🚕', 'travel')),
    MapEntry('metro', MapEntry('🚕', 'travel')),
    MapEntry('iocl', MapEntry('⛽', 'fuel')),
    MapEntry('bpcl', MapEntry('⛽', 'fuel')),
    MapEntry('hpcl', MapEntry('⛽', 'fuel')),
    MapEntry('shell', MapEntry('⛽', 'fuel')),
    MapEntry('petrol', MapEntry('⛽', 'fuel')),
    MapEntry('pump', MapEntry('⛽', 'fuel')),
    // Bills
    MapEntry('electricity', MapEntry('💡', 'bills')),
    MapEntry('water', MapEntry('💡', 'bills')),
    MapEntry('broadband', MapEntry('💡', 'bills')),
    MapEntry('wifi', MapEntry('💡', 'bills')),
    MapEntry('jio', MapEntry('💡', 'bills')),
    MapEntry('airtel', MapEntry('💡', 'bills')),
    MapEntry('vodafone', MapEntry('💡', 'bills')),
    MapEntry('bsnl', MapEntry('💡', 'bills')),
    MapEntry('recharge', MapEntry('💡', 'bills')),
    MapEntry('bill', MapEntry('💡', 'bills')),
    // Shopping
    MapEntry('amazon', MapEntry('🛍️', 'shopping')),
    MapEntry('flipkart', MapEntry('🛍️', 'shopping')),
    MapEntry('myntra', MapEntry('🛍️', 'shopping')),
    MapEntry('ajio', MapEntry('🛍️', 'shopping')),
    MapEntry('nykaa', MapEntry('🛍️', 'shopping')),
    MapEntry('mall', MapEntry('🛍️', 'shopping')),
    // Health
    MapEntry('apollo', MapEntry('💊', 'health')),
    MapEntry('pharmacy', MapEntry('💊', 'health')),
    MapEntry('hospital', MapEntry('💊', 'health')),
    MapEntry('clinic', MapEntry('💊', 'health')),
    MapEntry('doctor', MapEntry('💊', 'health')),
    MapEntry('diagnostic', MapEntry('💊', 'health')),
    // Education
    MapEntry('byjus', MapEntry('📚', 'education')),
    MapEntry('udemy', MapEntry('📚', 'education')),
    MapEntry('coursera', MapEntry('📚', 'education')),
    MapEntry('tuition', MapEntry('📚', 'education')),
    MapEntry('fee', MapEntry('📚', 'education')),
    // Rent
    MapEntry('rent', MapEntry('🏠', 'rent')),
    MapEntry('landlord', MapEntry('🏠', 'rent')),
    MapEntry('pg', MapEntry('🏠', 'rent')),
    MapEntry('hostel', MapEntry('🏠', 'rent')),
    // Transfer / UPI apps / Wallet
    MapEntry('phonepe', MapEntry('💸', 'transfer')),
    MapEntry('gpay', MapEntry('💸', 'transfer')),
    MapEntry('paytm', MapEntry('💸', 'transfer')),
    MapEntry('upi', MapEntry('💸', 'transfer')),
    MapEntry('self', MapEntry('💸', 'transfer')),
    MapEntry('transfer', MapEntry('💸', 'transfer')),
    MapEntry('imps', MapEntry('💸', 'transfer')),
    MapEntry('neft', MapEntry('💸', 'transfer')),
    MapEntry('rtgs', MapEntry('💸', 'transfer')),
    MapEntry('wallet', MapEntry('💸', 'transfer')),
    // Entertainment
    MapEntry('netflix', MapEntry('🎬', 'entertainment')),
    MapEntry('prime', MapEntry('🎬', 'entertainment')),
    MapEntry('spotify', MapEntry('🎬', 'entertainment')),
    MapEntry('cinema', MapEntry('🎬', 'entertainment')),
    MapEntry('pvr', MapEntry('🎬', 'entertainment')),
    MapEntry('inox', MapEntry('🎬', 'entertainment')),
    MapEntry('movie', MapEntry('🎬', 'entertainment')),
    MapEntry('playstore', MapEntry('🎬', 'entertainment')),
    MapEntry('appstore', MapEntry('🎬', 'entertainment')),
  ];

  static String categoryFor(String emoji, {Map<String, String>? custom}) {
    if (custom != null && custom.containsKey(emoji)) return custom[emoji]!;
    return categories[emoji] ?? 'other';
  }

  static List<String> get emojis => categories.keys.toList();

  /// Auto-categorize a merchant string. Returns [emoji, category] or null if unknown.
  static MapEntry<String, String>? categorizeMerchant(String merchant, {Map<String, String>? custom}) {
    final m = merchant.toLowerCase();
    // Check custom overrides first
    if (custom != null) {
      for (final entry in custom.entries) {
        if (m.contains(entry.key.toLowerCase())) {
          return MapEntry(entry.key, entry.value);
        }
      }
    }
    for (final rule in merchantRules) {
      if (m.contains(rule.key)) {
        return MapEntry(rule.value.key, rule.value.value);
      }
    }
    return null;
  }
}
