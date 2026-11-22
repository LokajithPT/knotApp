import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/transaction.dart';
import 'knot_service.dart';
import 'money_service.dart';
import 'settings_service.dart';

class SyncService {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();

  SyncService._();

  String get _serverUrl {
    final url = SettingsService.settings.syncServerUrl.trim();
    if (url.isEmpty) return '';
    final u = url.endsWith('/') ? url : '$url/';
    return u;
  }

  bool get isConfigured => _serverUrl.isNotEmpty && SettingsService.settings.syncEnabled;

  /// Last successful sync timestamp (ISO8601). Stored locally so we only pull changes since then.
  static String? _lastSync;
  static bool _syncing = false;
  static final ValueNotifier<bool> syncingNotifier = ValueNotifier(false);
  static final ValueNotifier<String?> lastSyncNotifier = ValueNotifier(null);
  static final ValueNotifier<int> pendingCountNotifier = ValueNotifier(0);

  /// ---------- Helpers ----------

  Future<http.Response> _get(String path) async {
    if (!_serverUrl.isNotEmpty) throw Exception('Sync server not configured');
    final uri = Uri.parse('$_serverUrl$path');
    return await http.get(uri).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> _post(String path, {Object? body}) async {
    if (!_serverUrl.isNotEmpty) throw Exception('Sync server not configured');
    final uri = Uri.parse('$_serverUrl$path');
    return await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
  }

  /// ---------- Health ----------

  Future<bool> ping() async {
    try {
      if (!_serverUrl.isNotEmpty) return false;
      final res = await _get('api/health');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// ---------- Pull (server -> phone) ----------

  Future<void> pullTransactions() async {
    if (!_serverUrl.isNotEmpty) return;
    final since = _lastSync ?? '';
    try {
      final res = await _get('api/sync/pull?since=$since');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final changes = data['changes'] as List? ?? [];
      for (final c in changes) {
        if (c['type'] == 'transaction' && c['op'] == 'upsert') {
          final d = c['data'];
          final tx = Transaction(
            id: d['id'],
            amount: (d['amount'] as num).toDouble(),
            type: d['tx_type'] ?? 'debit',
            merchant: d['merchant'] ?? '',
            accountMask: d['accountMask'],
            upiRef: d['upiRef'],
            upiId: d['upiId'],
            balance: d['balance'] != null ? (d['balance'] as num).toDouble() : null,
            date: d['date'] != null ? DateTime.parse(d['date']) : DateTime.now(),
            sender: d['sender'] ?? '',
            rawBody: d['rawBody'],
            emoji: d['emoji'],
            category: d['category'],
            isOrganized: d['isOrganized'] ?? false,
            reason: d['reason'],
            bank: d['bank'],
            source: d['source'] ?? 'sms',
            confidence: (d['confidence'] as num?)?.toDouble() ?? 1.0,
          );
          await MoneyService.upsertTransaction(tx);
        }
      }
    } catch (e) {
      if (kDebugMode) print('Sync pull transactions error: $e');
    }
  }

  Future<void> pullProjectsAndNotes() async {
    if (!_serverUrl.isNotEmpty) return;
    try {
      final res = await _get('api/projects');
      if (res.statusCode != 200) return;
      final projects = jsonDecode(res.body) as List?;
      if (projects == null) return;
      for (final p in projects) {
        final name = p['name'] as String?;
        if (name == null) continue;
        // Pull notes for this project
        try {
          final notesRes = await _get('api/projects/$name/notes');
          if (notesRes.statusCode != 200) continue;
          final notes = jsonDecode(notesRes.body) as List?;
          if (notes == null) continue;
          for (final n in notes) {
            await _upsertNote(name, n);
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) print('Sync pull projects error: $e');
    }
  }

  Future<void> _upsertNote(String projectName, Map<String, dynamic> n) async {
    final knotDir = await KnotService.getKnotDir();
    final projectPath = '$knotDir/$projectName';
    await Directory(projectPath).create(recursive: true);
    final noteName = n['name'] as String? ?? 'note.md';
    final content = n['content'] as String? ?? '';
    final isVoice = n['is_voice'] as bool? ?? false;
    final filePath = '$projectPath/$noteName';
    final file = File(filePath);
    if (!await file.exists() ||
        (n['updated_at'] != null &&
            DateTime.parse(n['updated_at']).isAfter(
              await file.lastModified().then((_) => file.lastModified()),
            ))) {
      await file.writeAsString(content);
      if (isVoice) {
        final voicePath = n['voice_path'] as String?;
        if (voicePath != null) {
          // Download voice file
          try {
            final voiceRes = await http
                .get(Uri.parse('$_serverUrl/api/files/$projectName/$noteName'))
                .timeout(const Duration(seconds: 15));
            if (voiceRes.statusCode == 200) {
              final voiceFile = File('$projectPath/$noteName.voice');
              await voiceFile.writeAsBytes(voiceRes.bodyBytes);
            }
          } catch (_) {}
        }
      }
    }
  }

  /// ---------- Push (phone -> server) ----------

  Future<void> pushTransactions() async {
    if (!_serverUrl.isNotEmpty) return;
    try {
      final txs = await MoneyService.loadTransactions();
      final changes = <Map<String, dynamic>>[];
      for (final t in txs) {
        changes.add({
          'type': 'transaction',
          'op': 'upsert',
          'id': t.id,
          'data': t.toJson(),
        });
      }
      if (changes.isEmpty) return;
      final res = await _post('api/sync/push', body: {'changes': changes});
      if (res.statusCode != 200) return;
    } catch (e) {
      if (kDebugMode) print('Sync push transactions error: $e');
    }
  }

  /// ---------- Full sync ----------

  Future<void> sync() async {
    if (!_syncing) {
      _syncing = true;
      syncingNotifier.value = true;
    }
    try {
      await pullTransactions();
      await pullProjectsAndNotes();
      await pushTransactions();
      _lastSync = DateTime.now().toIso8601String();
      lastSyncNotifier.value = _lastSync ?? '';
      pendingCountNotifier.value = 0;
    } finally {
      _syncing = false;
      syncingNotifier.value = false;
    }
  }

  /// ---------- WebSocket stream ----------

  /// Connect to the server WebSocket and listen for real-time updates.
  /// [onMessage] is called with each received message.
  Future<void> connectWebSocket(void Function(String) onMessage) async {
    if (!_serverUrl.isNotEmpty) return;
    // Note: dart:io WebSocket for mobile; using raw HTTP polling fallback if needed.
    // For now, WebSocket support is a stub that can be extended with web_socket_channel.
    if (kDebugMode) print('WebSocket stream: server=$_serverUrl');
  }

  /// Get pending count (transactions not yet organized)
  Future<int> getPendingCount() async {
    if (!_serverUrl.isNotEmpty) return 0;
    try {
      final pending = await MoneyService.getPending();
      return pending.length;
    } catch (_) {
      return 0;
    }
  }

  /// Refresh notifiers
  void refresh() {
    getPendingCount().then((v) => pendingCountNotifier.value = v);
  }
}
