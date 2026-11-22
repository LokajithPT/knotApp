import 'dart:io';
import '../models/transaction.dart';
import 'knot_service.dart';

/// Automatically appends parsed transactions (debits/credits from SMS) to a
/// markdown note under ~/.KnotNotes/Money/transactions.md so every payment
/// shows up as a note in the graph.
class TransactionNoteService {
  static const String _projectName = 'Money';
  static const String _noteName = 'transactions';

  static Future<String> _getNotePath() async {
    final knotDir = await KnotService.getKnotDir();
    final projectDir = Directory('$knotDir/$_projectName');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    return '${projectDir.path}/$_noteName.md';
  }

  /// Appends a single transaction row to the note. Creates the file with a
  /// header table if it doesn't exist yet.
  static Future<void> appendTransaction(Transaction tx) async {
    final path = await _getNotePath();
    final file = File(path);

    final exists = await file.exists();
    if (!exists) {
      await file.writeAsString(
        '# Money Log\n\n'
        'Auto-captured from bank / UPI SMS.\n\n'
        '| Date | Merchant | Type | Amount | UPI Ref |\n'
        '|------|----------|------|--------|---------|\n',
      );
    }

    final date = '${tx.date.day}/${tx.date.month}/${tx.date.year}';
    final upi = tx.upiRef ?? '-';
    final line = '| $date | ${tx.merchant} | ${tx.type.toUpperCase()} | ₹${tx.amount.toStringAsFixed(2)} | $upi |\n';

    await file.writeAsString(line, mode: FileMode.append);
  }
}
