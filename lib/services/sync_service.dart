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

  /// Last successful sync timestamp (ISO8601).
  static String? _lastSync;
  static bool _syncing = false;
  static final ValueNotifier<bool> syncingNotifier = ValueNotifier(false);
  static final ValueNotifier<String?> lastSyncNotifier = ValueNotifier(null);
  static final ValueNotifier<int> pendingCountNotifier = ValueNotifier(0);

  /// ---------- Progress UI notifiers ----------

  /// 0.0 to 1.0
  static final ValueNotifier<double> syncProgressNotifier = ValueNotifier(0.0);

  /// Human-readable current step (e.g. "Sending transaction 3 of 12")
  static final ValueNotifier<String> syncStatusNotifier = ValueNotifier('Idle');

  /// Recent log lines (newest first)
  static final ValueNotifier<List<String>> syncLogNotifier = ValueNotifier([]);

  static void _log(String msg) {
    final time = DateTime.now().toString().substring(11, 19);
    final line = '[$time] $msg';
    if (kDebugMode) print('[SYNC] $line');
    syncStatusNotifier.value = msg;
    final list = List<String>.from(syncLogNotifier.value);
    list.insert(0, line);
    if (list.length > 100) list.removeLast();
    syncLogNotifier.value = list;
  }

  static void _setProgress(double p) {
    syncProgressNotifier.value = p.clamp(0.0, 1.0);
  }

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
    _log('Pulling transactions since $since...');
    try {
      final res = await _get('sync/pull?since=${Uri.encodeComponent(since)}');
      if (res.statusCode != 200) {
        _log('Pull transactions failed: HTTP ${res.statusCode}');
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final changes = data['changes'] as List? ?? [];
      _log('Found ${changes.length} transaction changes');
      int count = 0;
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
          count++;
          _setProgress(0.25 + (0.25 * count / changes.length.clamp(1, 1)));
          _log('Received tx: ${tx.merchant} (${tx.amount})');
        }
      }
      _log('Transactions pulled: $count');
    } catch (e) {
      _log('Pull transactions error: $e');
    }
  }

  Future<void> pullProjectsAndNotes() async {
    if (!_serverUrl.isNotEmpty) return;
    _log('Pulling projects and notes...');
    try {
      final res = await _get('projects');
      if (res.statusCode != 200) {
        _log('Pull projects failed: HTTP ${res.statusCode}');
        return;
      }
      final projects = jsonDecode(res.body) as List?;
      if (projects == null) {
        _log('No projects returned');
        return;
      }
      _log('Found ${projects.length} projects');
      int projDone = 0;
      for (final p in projects) {
        final name = p['name'] as String?;
        if (name == null) continue;
        projDone++;
        _setProgress(0.5 + (0.25 * projDone / projects.length));
        _log('Pulling notes for project: $name');
        try {
          final notesRes = await _get('projects/$name/notes');
          if (notesRes.statusCode != 200) {
            _log('  Notes for $name failed: HTTP ${notesRes.statusCode}');
            continue;
          }
          final notes = jsonDecode(notesRes.body) as List?;
          if (notes == null) continue;
          _log('  Found ${notes.length} notes in $name');
          int noteDone = 0;
          for (final n in notes) {
            noteDone++;
            await _upsertNote(name, n);
            _log('  Synced note: ${n['name'] ?? '?'}');
          }
        } catch (e) {
          _log('  Notes error for $name: $e');
        }
      }
      _log('Projects and notes pulled');
    } catch (e) {
      _log('Pull projects error: $e');
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
          try {
            final voiceRes = await _get('files/$voicePath');
            if (voiceRes.statusCode == 200) {
              final voiceFile = File('$projectPath/$noteName.voice');
              await voiceFile.writeAsBytes(voiceRes.bodyBytes);
              _log('  Downloaded voice: $voicePath');
            }
          } catch (_) {}
        }
      }
    }
  }

  /// ---------- Push (phone -> server) ----------

  Future<void> pushTransactions() async {
    if (!_serverUrl.isNotEmpty) return;
    _log('Pushing transactions to server...');
    try {
      final txs = await MoneyService.loadTransactions();
      if (txs.isEmpty) {
        _log('No transactions to push');
      } else {
        _log('Found ${txs.length} local transactions');
        final changes = <Map<String, dynamic>>[];
        for (final t in txs) {
          changes.add({
            'type': 'transaction',
            'op': 'upsert',
            'id': t.id,
            'data': t.toJson(),
          });
        }
        int sent = 0;
        for (final c in changes) {
          sent++;
          _log('Sending transaction ${c['id']}: ${c['data']['merchant'] ?? '?'}');
        }
        final res = await _post('sync/push', body: {'changes': changes});
        if (res.statusCode != 200) {
          _log('Push transactions failed: HTTP ${res.statusCode}');
          return;
        }
        _log('Transactions pushed: ${txs.length}');
      }
    } catch (e) {
      _log('Push transactions error: $e');
    }
  }

  /// Push all local notes (text + voice) to the server.
  Future<void> pushNotes() async {
    if (!_serverUrl.isNotEmpty) return;
    _log('Pushing notes to server...');
    try {
      final allNotes = await KnotService.getAllProjectNotes();
      if (allNotes.isEmpty) {
        _log('No local notes to push');
        return;
      }

      int totalNotes = allNotes.values.expand((v) => v).length;
      _log('Found $totalNotes local notes across ${allNotes.length} projects');

      int sent = 0;
      for (final entry in allNotes.entries) {
        final projectName = entry.key;
        final noteNames = entry.value;

        for (final noteName in noteNames) {
          sent++;
          _log('Sending note: $projectName/$noteName');

          final knotDir = await KnotService.getKnotDir();
          final projectPath = '$knotDir/$projectName';
          final mdPath = '$projectPath/$noteName.md';

          String content = '';
          bool isVoice = false;
          String? voicePath;

          final mdFile = File(mdPath);
          if (await mdFile.exists()) {
            content = await mdFile.readAsString();
          } else {
            // It's a voice note (.m4a / .wav / .webm without .md)
            isVoice = true;
            for (final ext in ['.m4a', '.wav', '.webm']) {
              final vf = File('$projectPath/$noteName$ext');
              if (await vf.exists()) {
                voicePath = '$noteName$ext';
                break;
              }
            }
          }

          // Upload voice file first if it exists
          if (voicePath != null) {
            final uploaded = await uploadFile(projectName, '$projectPath/$voicePath');
            if (uploaded != null) {
              voicePath = uploaded;
              _log('  Voice uploaded: $uploaded');
            }
          }

          final change = {
            'type': 'note',
            'op': 'upsert',
            'id': '$projectName:$noteName',
            'data': {
              'project': projectName,
              'name': noteName,
              'content': content,
              'is_voice': isVoice,
              'voice_path': voicePath,
            },
          };

          final res = await _post('sync/push', body: {'changes': [change]});
          if (res.statusCode != 200) {
            _log('  Failed to push $noteName: HTTP ${res.statusCode}');
          }
        }
      }
      _log('Notes pushed: $sent');
    } catch (e) {
      _log('Push notes error: $e');
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
      _log('Upload file error: $e');
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

  /// ---------- Full sync with progress ----------

  Future<void> sync() async {
    if (!_serverUrl.isNotEmpty) {
      _log('Sync aborted: server not configured');
      return;
    }
    if (_syncing) {
      _log('Sync already running');
      return;
    }

    _syncing = true;
    syncingNotifier.value = true;
    syncProgressNotifier.value = 0.0;
    syncLogNotifier.value = [];
    _log('Starting sync...');

    try {
      // Phase 1: Pull transactions (0 - 20%)
      await pullTransactions();
      _setProgress(0.20);

      // Phase 2: Pull projects & notes (20 - 40%)
      await pullProjectsAndNotes();
      _setProgress(0.40);

      // Phase 3: Push transactions (40 - 70%)
      await pushTransactions();
      _setProgress(0.70);

      // Phase 4: Push notes (70 - 100%)
      await pushNotes();
      _setProgress(1.0);

      _lastSync = DateTime.now().toIso8601String();
      lastSyncNotifier.value = _lastSync ?? '';
      _log('Sync complete at $_lastSync');
    } catch (e) {
      _log('Sync error: $e');
    } finally {
      _syncing = false;
      syncingNotifier.value = false;
    }
  }

  /// ---------- WebSocket stream ----------

  Future<void> connectWebSocket(void Function(String) onMessage) async {
    if (!_serverUrl.isNotEmpty) return;
    final wsUrl = _serverUrl.replaceFirst('http', 'ws') + 'sync/stream';
    _log('Connecting WebSocket: $wsUrl');
    try {
      final channel = await WebSocket.connect(
        wsUrl,
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 10));
      _log('WebSocket connected');
      channel.listen(
        (data) => onMessage(data as String),
        onError: (e) => _log('WS error: $e'),
        onDone: () => _log('WS closed'),
      );
    } catch (e) {
      _log('WebSocket connect error: $e');
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
