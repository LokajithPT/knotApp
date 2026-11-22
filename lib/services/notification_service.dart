import 'package:flutter/material.dart';
import '../models/transaction.dart';
import 'money_service.dart';
import 'emoji_service.dart';

class NotificationService {
  static void showStubbornEmojiPicker(BuildContext context, Transaction tx, {VoidCallback? onAssigned}) {
    final customEmojiCtrl = TextEditingController();
    final customCatCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: tx.reason ?? '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1a1a2e),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [Icon(Icons.warning_amber, color: Color(0xFFff006e)), SizedBox(width: 8), Text('Categorize', style: TextStyle(color: Color(0xFFff006e), fontSize: 16, fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 8),
                  Text('${tx.merchant} • INR ${tx.amount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 14)),
                  Text('${tx.type.toUpperCase()} on ${tx.date.day}/${tx.date.month}/${tx.date.year}', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  const SizedBox(height: 6),
                  Text(tx.rawBody, style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pick an emoji. This won’t go away until you do. Add a reason if you want.', style: TextStyle(color: Color(0xFFe0e0e0), fontSize: 12)),
                    const SizedBox(height: 12),
                    FutureBuilder<Map<String, String>>(
                      future: EmojiService.loadCustom(),
                      builder: (_, snap) {
                        final custom = snap.data ?? {};
                        final all = [...EmojiCategory.emojis, ...custom.keys];
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: all.map((emoji) {
                            final cat = EmojiCategory.categoryFor(emoji, custom: custom);
                            return GestureDetector(
                              onTap: () async {
                                final reason = reasonCtrl.text.trim();
                                await MoneyService.setEmoji(tx.id, emoji, reason: reason.isEmpty ? null : reason);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (onAssigned != null) onAssigned();
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $emoji $cat', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF00d4ff), duration: const Duration(seconds: 1)));
                              },
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(color: const Color(0xFF2d2d44), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF00d4ff).withOpacity(0.2))),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(emoji, style: const TextStyle(fontSize: 22)), const SizedBox(height: 2), Text(cat, style: TextStyle(color: Colors.grey[500], fontSize: 8), overflow: TextOverflow.ellipsis)]),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF2d2d44)),
                    const SizedBox(height: 8),
                    const Align(alignment: Alignment.centerLeft, child: Text('Custom emoji', style: TextStyle(color: Color(0xFF7b2cbf), fontSize: 12, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 8),
                    Row(children: [
                      SizedBox(width: 60, child: TextField(controller: customEmojiCtrl, style: const TextStyle(color: Colors.white, fontSize: 20), textAlign: TextAlign.center, decoration: InputDecoration(hintText: '😀', hintStyle: TextStyle(color: Colors.grey[600]), filled: true, fillColor: const Color(0xFF2d2d44), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 10)))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: customCatCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'category e.g. gifts', hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12), filled: true, fillColor: const Color(0xFF2d2d44), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
                      const SizedBox(width: 8),
                      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00d4ff), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () async { final e = customEmojiCtrl.text.trim(); final c = customCatCtrl.text.trim(); if (e.isEmpty || c.isEmpty) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter emoji + category'))); return; } await EmojiService.addCustom(e, c); setLocal(() {}); }, child: const Text('Add', style: TextStyle(color: Colors.white))),
                    ]),
                    const SizedBox(height: 12),
                    TextField(controller: reasonCtrl, style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 2, decoration: InputDecoration(hintText: 'Reason / description (optional) — e.g. lunch with team', hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12), filled: true, fillColor: const Color(0xFF2d2d44), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7b2cbf), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () async { final e = customEmojiCtrl.text.trim(); if (e.isEmpty) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Pick or type an emoji first'))); return; } final c = customCatCtrl.text.trim(); if (c.isNotEmpty) await EmojiService.addCustom(e, c); final reason = reasonCtrl.text.trim(); await MoneyService.setEmoji(tx.id, e, reason: reason.isEmpty ? null : reason, customCategory: c.isEmpty ? null : c); if (ctx.mounted) Navigator.pop(ctx); if (onAssigned != null) onAssigned(); }, child: const Text('Save custom emoji + reason', style: TextStyle(color: Colors.white, fontSize: 12)))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> showNextPending(BuildContext context) async {
    final pending = await MoneyService.getPending();
    if (pending.isEmpty) return;
    if (!context.mounted) return;
    showStubbornEmojiPicker(context, pending.first, onAssigned: () {
      Future.delayed(const Duration(milliseconds: 400), () { if (context.mounted) showNextPending(context); });
    });
  }
}
