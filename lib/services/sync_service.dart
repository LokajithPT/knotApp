import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/transaction.dart';
import 'knot_service.dart';
import 'money_service.dart';
import 'settings_service.dart';

/// Shared secret key sent with every request. No JWT — just a constant key.
const String _apiKey = 'knot-sync-key-2024';

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

  Map<String, String> _authHeaders() => {
    'Authorization': 'Bearer $_apiKey',
  };

  Future<http.Response> _get(String path) async {
    if (!_serverUrl.isNotEmpty) throw Exception('Sync server not configured');
    final uri = Uri.parse('$_serverUrl$path');
    return await http.get(uri, headers: _authHeaders()).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> _post(String path, {Object? body, Map<String, String>? extraHeaders}) async {
    if (!_serverUrl.isNotEmpty) throw Exception('Sync server not configured');
    final uri = Uri.parse('$_serverUrl$path');
    final headers = <String, String>{..._authHeaders(), ...?extraHeaders};
    return await http.post(
      uri,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
  }

  /// ---------- Health ----------

  Future<bool> ping() async {
    try {
      if (!_serverUrl.isNotEmpty) return false;
      final res = await _get('health');
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
      final res = await _get('sync/pull?since=${Uri.encodeComponent(since)}');
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
      final res = await _get('projects');
      if (res.statusCode != 200) return;
      final projects = jsonDecode(res.body) as List?;
      if (projects == null) return;
      for (final p in projects) {
        final name = p['name'] as String?;
        if (name == null) continue;
        try {
          final notesRes = await _get('projects/$name/notes');
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
    bool shouldWrite = !await file.exists();
    if (!shouldWrite && n['updated_at'] != null) {
      try {
        final modified = await file.lastModified();
        shouldWrite = DateTime.parse(n['updated_at']).isAfter(modified);
      } catch (_) {
        shouldWrite = true;
      }
    }
    if (shouldWrite) {
      await file.writeAsString(content);
      if (isVoice) {
        final voicePath = n['voice_path'] as String?;
        if (voicePath != null) {
          // Download voice attachment from server
          try {
            final voiceRes = await _get('files/$voicePath');
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
      final res = await _post('sync/push', body: {'changes': changes});
      if (res.statusCode != 200) return;
      if (kDebugMode) print('Sync push: ${res.body}');
    } catch (e) {
      if (kDebugMode) print('Sync push transactions error: $e');
    }
  }

  /// Upload a file (audio / image) to the server. Returns the server filename.
  Future<String?> uploadFile(String projectName, String filePath, {String? noteName}) async {
    if (!_serverUrl.isNotEmpty) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);
      final body = jsonEncode({
        'filename': filePath.split('/').last,
        'mime_type': _mimeFor(filePath),
        'data': base64,
      });

      final res = await http.post(
        Uri.parse('$_serverUrl/files/upload'),
        headers: {..._authHeaders(), 'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final files = data['files'] as List?;
      if (files == null || files.isEmpty) return null;
      return files[0]['filename'] as String?;
    } catch (e) {
      if (kDebugMode) print('Upload file error: $e');
      return null;
    }
  }

  String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.webm')) return 'audio/webm';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
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

  /// Connect to the server WebSocket and listen for real-time sync events.
  /// [onMessage] is called with each received JSON string message.
  Future<void> connectWebSocket(void Function(String) onMessage) async {
    if (!_serverUrl.isNotEmpty) return;
    final wsUrl = _serverUrl.replaceFirst('http', 'ws') + 'sync/stream';
    try {
      // Use dart:io WebSocket for mobile. Falls back silently on web.
      final channel = await WebSocket.connect(
        wsUrl,
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 10));

      channel.listen(
        (data) => onMessage(data as String),
        onError: (e) => ifDebug('WS error: $e'),
        onDone: () => ifDebug('WS closed'),
      );
    } catch (e) {
      if (kDebugMode) print('WebSocket connect error: $e');
    }
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

void ifDebug(String msg) {
  if (kDebugMode) print(msg);
}