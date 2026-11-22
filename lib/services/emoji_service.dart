import 'dart:io';
import 'dart:convert';
import 'knot_service.dart';

class EmojiService {
  static String? _dir;
  static Future<String> _path() async {
    if (_dir != null) return '$_dir/custom_emojis.json';
    final knotDir = await KnotService.getKnotDir();
    _dir = '$knotDir/_money';
    final d = Directory(_dir!);
    if (!await d.exists()) await d.create(recursive: true);
    return '$_dir/custom_emojis.json';
  }

  static Future<Map<String, String>> loadCustom() async {
    final p = await _path();
    final f = File(p);
    if (!await f.exists()) return {};
    try {
      final c = await f.readAsString();
      if (c.trim().isEmpty) return {};
      final Map decoded = jsonDecode(c);
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> addCustom(String emoji, String category) async {
    emoji = emoji.trim();
    category = category.trim().toLowerCase();
    if (emoji.isEmpty || category.isEmpty) return;
    final map = await loadCustom();
    map[emoji] = category;
    final p = await _path();
    await File(p).writeAsString(jsonEncode(map));
  }

  static Future<void> removeCustom(String emoji) async {
    final map = await loadCustom();
    map.remove(emoji);
    final p = await _path();
    await File(p).writeAsString(jsonEncode(map));
  }
}
