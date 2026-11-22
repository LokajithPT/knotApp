import 'dart:async';
import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/money_service.dart';
import '../services/emoji_service.dart';
import '../services/notification_service.dart';
import '../services/sms_receiver.dart';

class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key});
  @override State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  List<Transaction> _txs = [];
  Map<String, String> _custom = {};
  bool _loading = true;
  String _filter = 'all'; // all | pending | organized
  DateTime? _selectedMonth;
  StreamSubscription? _smsSub;

  @override void initState() { super.initState(); _load(); _listenSms(); }

  @override void dispose() { _smsSub?.cancel(); super.dispose(); }

  void _listenSms() {
    _smsSub = SmsReceiverService.onTransactionReceived.listen((tx) {
      if (!mounted) return;
      setState(() => _txs.insert(0, tx));
      if (tx.needsEmoji) {
        NotificationService.showStubbornEmojiPicker(context, tx, onAssigned: _load);
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final txs = await MoneyService.loadTransactions();
    final custom = await EmojiService.loadCustom();
    setState(() { _txs = txs; _custom = custom; _loading = false; });
    if (_txs.any((t) => t.needsEmoji) && mounted) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) NotificationService.showNextPending(context);
      });
    }
  }

  List<Transaction> get _filtered {
    final m = _selectedMonth ?? DateTime.now();
    var list = _txs.where((t) => t.date.year == m.year && t.date.month == m.month).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    if (_filter == 'pending') list = list.where((t) => t.needsEmoji).toList();
    if (_filter == 'organized') list = list.where((t) => !t.needsEmoji).toList();
    return list;
  }

  Future<void> _promptManualSms() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Paste SMS', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold)),
      content: TextField(controller: ctrl, maxLines: 5, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Paste bank SMS here...', hintStyle: TextStyle(color: Colors.grey[600]), filled: true, fillColor: const Color(0xFF2d2d44), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Parse', style: TextStyle(color: Color(0xFF00d4ff)))),
      ],
    ));
    if (res != null && res.isNotEmpty) {
      final tx = await MoneyService.ingestSms('Manual', res);
      if (tx == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not a financial SMS'), backgroundColor: Color(0xFFff006e)));
      } else if (tx != null) {
        await _load();
        if (tx.needsEmoji && mounted) NotificationService.showStubbornEmojiPicker(context, tx, onAssigned: _load);
      }
    }
  }

  Future<void> _editTransaction(Transaction t) async {
    final amtCtrl = TextEditingController(text: t.amount.toStringAsFixed(2));
    final merchCtrl = TextEditingController(text: t.merchant);
    final reasonCtrl = TextEditingController(text: t.reason ?? '');
    String type = t.type;
    DateTime date = t.date;
    String? emoji = t.emoji;
    String? category = t.category;

    final res = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Transaction', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: TextField(controller: amtCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Amount (₹)', labelStyle: TextStyle(color: Colors.grey[500]), filled: true, fillColor: const Color(0xFF2d2d44), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
              const SizedBox(width: 10),
              Container(width: 90, child: DropdownButton<String>(
                value: type, dropdownColor: const Color(0xFF2d2d44),
                style: const TextStyle(color: Colors.white),
                items: const [DropdownMenuItem(value: 'debit', child: Text('Debit', style: TextStyle(color: Colors.white))), DropdownMenuItem(value: 'credit', child: Text('Credit', style: TextStyle(color: Colors.white)))],
                onChanged: (v) => setLocal(() => type = v!),
              )),
            ]),
            const SizedBox(height: 10),
            TextField(controller: merchCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Merchant', labelStyle: TextStyle(color: Colors.grey[500]), filled: true, fillColor: const Color(0xFF2d2d44), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
            const SizedBox(height: 10),
            Row(children: [
              Text('${date.day}/${date.month}/${date.year}', style: TextStyle(color: Colors.grey[500])),
              const Spacer(),
              TextButton(onPressed: () async {
                final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (picked != null) setLocal(() => date = picked);
              }, child: const Text('Pick date', style: TextStyle(color: Color(0xFF00d4ff)))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Text(emoji ?? '❓', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(child: Text(category ?? (emoji != null ? EmojiCategory.categoryFor(emoji!) : 'uncategorized'), style: TextStyle(color: Colors.grey[500]))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: EmojiCategory.emojis.map((e) {
              final selected = emoji == e;
              return ChoiceChip(label: Text(e), selected: selected, onSelected: (_) => setLocal(() { emoji = e; category = EmojiCategory.categoryFor(e, custom: _custom); }), labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey[500]), selectedColor: const Color(0xFF00d4ff));
            }).toList()),
            const SizedBox(height: 10),
            TextField(controller: reasonCtrl, maxLines: 2, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Reason (optional)', labelStyle: TextStyle(color: Colors.grey[500]), filled: true, fillColor: const Color(0xFF2d2d44), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
          ElevatedButton(onPressed: () {
            final amt = double.tryParse(amtCtrl.text.replaceAll(RegExp(r'[^0-9.]'), ''));
            if (amt == null || amt <= 0) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter a valid amount'))); return; }
            Navigator.pop(ctx, true);
          }, child: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      ),
    ));
    if (res == true && mounted) {
      await MoneyService.updateTransaction(t.id,
        amount: double.tryParse(amtCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? t.amount,
        type: type,
        merchant: merchCtrl.text.trim().isEmpty ? t.merchant : merchCtrl.text.trim(),
        date: date,
        emoji: emoji,
        category: category,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        isOrganized: emoji != null,
      );
      await _load();
    }
  }

  Future<void> _deleteTransaction(Transaction t) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      title: const Text('Delete?', style: TextStyle(color: Color(0xFFff006e))),
      content: Text('Remove "${t.merchant}"?', style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFff006e)))),
      ],
    ));
    if (ok == true && mounted) {
      await MoneyService.deleteTransaction(t.id);
      await _load();
    }
  }

  String _bankLabel(Transaction t) {
    final parts = <String>[];
    if (t.bank != null) parts.add(t.bank!.toUpperCase());
    if (t.accountMask != null) parts.add('••••${t.accountMask}');
    if (t.upiRef != null) parts.add('UPI ${t.upiRef}');
    if (t.upiId != null) parts.add(t.upiId!);
    if (parts.isEmpty) return t.sender;
    return parts.join('  ');
  }

  @override Widget build(BuildContext context) {
    final pendingCount = _txs.where((t) => t.needsEmoji).length;
    final summary = _calcSummary();
    final month = _selectedMonth ?? DateTime.now();
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f), elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF00d4ff)), onPressed: () => Navigator.pop(context)),
        title: const Text('Money', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today, color: Color(0xFF00d4ff)), onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: month, firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (picked != null) setState(() => _selectedMonth = DateTime(picked.year, picked.month));
          }),
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF7b2cbf)), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00d4ff)))
          : Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _statCard('Spent', '₹${summary['spent']!.toStringAsFixed(0)}', const Color(0xFFff006e)),
            const SizedBox(width: 10),
            _statCard('Income', '₹${summary['income']!.toStringAsFixed(0)}', const Color(0xFF00ff88)),
            const SizedBox(width: 10),
            _statCard('Pending', '$pendingCount', const Color(0xFF7b2cbf)),
          ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _chip('All', _filter == 'all', () => setState(() => _filter = 'all')),
            const SizedBox(width: 8),
            _chip('Pending', _filter == 'pending', () => setState(() => _filter = 'pending')),
            const SizedBox(width: 8),
            _chip('Organized', _filter == 'organized', () => setState(() => _filter = 'organized')),
            const Spacer(),
            if (pendingCount > 0)
              TextButton(onPressed: () => NotificationService.showNextPending(context), child: const Text('Categorize now', style: TextStyle(color: Color(0xFFff006e), fontSize: 12))),
          ])),
        const SizedBox(height: 8),
        Expanded(child: _buildList()),
      ]),
      floatingActionButton: _buildFabColumn(),
    );
  }

  Widget _buildFabColumn() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FloatingActionButton.small(heroTag: 'sim', backgroundColor: const Color(0xFF7b2cbf), onPressed: _promptManualSms, child: const Icon(Icons.sms, color: Colors.white), tooltip: 'Paste SMS'),
      const SizedBox(height: 8),
      FloatingActionButton(heroTag: 'add', backgroundColor: const Color(0xFF00d4ff), onPressed: _promptManualSms, child: const Icon(Icons.add, color: Colors.white), tooltip: 'Add / paste transaction'),
    ]);
  }

  Map<String, double> _calcSummary() {
    double spent = 0, income = 0;
    for (final t in _filtered) {
      if (t.type == 'debit') spent += t.amount; else income += t.amount;
    }
    return {'spent': spent, 'income': income};
  }

  Widget _statCard(String l, String v, Color c) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFF1a1a2e), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF2d2d44))),
    child: Column(children: [Text(v, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 2), Text(l, style: TextStyle(color: Colors.grey[600], fontSize: 10))]),
  ));

  Widget _chip(String l, bool sel, VoidCallback t) => GestureDetector(
    onTap: t,
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: sel ? const Color(0xFF00d4ff) : const Color(0xFF1a1a2e), borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? const Color(0xFF00d4ff) : const Color(0xFF2d2d44))),
      child: Text(l, style: TextStyle(color: sel ? Colors.white : Colors.grey[500], fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal))),
  );

  Widget _buildList() {
    final filtered = _filtered;
    if (filtered.isEmpty) return Center(child: Text('No transactions', style: TextStyle(color: Colors.grey[600])));
    final groups = <String, List<Transaction>>{};
    for (final t in filtered) {
      final k = t.emoji ?? '❓';
      groups.putIfAbsent(k, () => []).add(t);
    }
    final keys = groups.keys.toList();
    return ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: keys.length, itemBuilder: (_, i) {
      final emoji = keys[i];
      final list = groups[emoji]!;
      final cat = EmojiCategory.categoryFor(emoji, custom: _custom);
      final total = list.fold<double>(0, (a, b) => a + b.amount);
      return Container(margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: const Color(0xFF1a1a2e), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF2d2d44))),
        child: ExpansionTile(
          initiallyExpanded: i == 0,
          iconColor: const Color(0xFF00d4ff), collapsedIconColor: Colors.grey[600],
          title: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF2d2d44), borderRadius: BorderRadius.circular(12)), child: Text(emoji, style: const TextStyle(fontSize: 20))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$cat • ${list.length}', style: const TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold, fontSize: 14)),
              Text('₹${total.toStringAsFixed(0)}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ])),
          ]),
          children: list.map((t) => _txRow(t)).toList(),
        ),
      );
    });
  }

  Widget _txRow(Transaction t) {
    final pending = t.needsEmoji;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF2d2d44), borderRadius: BorderRadius.circular(10), border: Border.all(color: pending ? const Color(0xFFff006e).withOpacity(0.3) : const Color(0xFF00d4ff).withOpacity(0.2))), child: Center(child: Text(t.emoji ?? '❓', style: const TextStyle(fontSize: 18)))),
      title: Row(children: [
        Expanded(child: Text(t.merchant, style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 14, fontWeight: FontWeight.w600))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: pending ? const Color(0xFFff006e).withOpacity(0.15) : const Color(0xFF00ff88).withOpacity(0.15), borderRadius: BorderRadius.circular(6)), child: Text('${t.type[0].toUpperCase()} ₹${t.amount.toStringAsFixed(0)}', style: TextStyle(color: pending ? const Color(0xFFff006e) : const Color(0xFF00ff88), fontSize: 11, fontWeight: FontWeight.bold))),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${t.date.day}/${t.date.month}/${t.date.year}  •  ${_bankLabel(t)}', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        if (t.confidence < 1.0) Text('Parse confidence: ${(t.confidence * 100).toStringAsFixed(0)}%', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
        if (t.reason != null && t.reason!.isNotEmpty) Text('📝 ${t.reason}', style: const TextStyle(color: Color(0xFF7b2cbf), fontSize: 11)),
      ]),
      trailing: pending ? const Icon(Icons.warning, color: Color(0xFFff006e), size: 18) : const Icon(Icons.check_circle, color: Color(0xFF00ff88), size: 16),
      onTap: () => _editTransaction(t),
      onLongPress: pending ? null : () => _deleteTransaction(t),
    );
  }
}
