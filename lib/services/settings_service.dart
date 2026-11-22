import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  double nodeGlowIntensity;
  double nodeSize;
  double edgeThickness;
  double edgeGlow;
  bool showEdges;
  double labelSize;
  double editorTextSize;
  bool floatingAnimation;
  int accentColorIndex;
  bool confirmBeforeDelete;
  bool lowEndDevice;
  bool globalStaticMode;
  String syncServerUrl;
  bool syncEnabled;

  AppSettings({
    this.nodeGlowIntensity = 50.0,
    this.nodeSize = 1.0,
    this.edgeThickness = 1.0,
    this.edgeGlow = 0.0,
    this.showEdges = true,
    this.labelSize = 1.0,
    this.editorTextSize = 1.0,
    this.floatingAnimation = true,
    this.accentColorIndex = 0,
    this.confirmBeforeDelete = true,
    this.lowEndDevice = false,
    this.globalStaticMode = false,
    this.syncServerUrl = '',
    this.syncEnabled = false,
  });

  Map<String, dynamic> toJson() => {
    'nodeGlowIntensity': nodeGlowIntensity,
    'nodeSize': nodeSize,
    'edgeThickness': edgeThickness,
    'edgeGlow': edgeGlow,
    'showEdges': showEdges,
    'labelSize': labelSize,
    'editorTextSize': editorTextSize,
    'floatingAnimation': floatingAnimation,
    'accentColorIndex': accentColorIndex,
    'confirmBeforeDelete': confirmBeforeDelete,
    'lowEndDevice': lowEndDevice,
    'globalStaticMode': globalStaticMode,
    'syncServerUrl': syncServerUrl,
    'syncEnabled': syncEnabled,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      nodeGlowIntensity: (json['nodeGlowIntensity'] ?? 50.0).toDouble(),
      nodeSize: (json['nodeSize'] ?? 1.0).toDouble(),
      edgeThickness: (json['edgeThickness'] ?? 1.0).toDouble(),
      edgeGlow: (json['edgeGlow'] ?? 0.0).toDouble(),
      showEdges: json['showEdges'] ?? true,
      labelSize: (json['labelSize'] ?? 1.0).toDouble(),
      editorTextSize: (json['editorTextSize'] ?? 1.0).toDouble(),
      floatingAnimation: json['floatingAnimation'] ?? true,
      accentColorIndex: json['accentColorIndex'] ?? 0,
      confirmBeforeDelete: json['confirmBeforeDelete'] ?? true,
      lowEndDevice: json['lowEndDevice'] ?? false,
      globalStaticMode: json['globalStaticMode'] ?? false,
      syncServerUrl: json['syncServerUrl'] ?? '',
      syncEnabled: json['syncEnabled'] ?? false,
    );
  }
}

class SettingsService {
  static AppSettings _settings = AppSettings();
  static bool _loaded = false;
  static final _onChangeCallbacks = <VoidCallback>[];

  static AppSettings get settings => _settings;

  static void addListener(VoidCallback callback) => _onChangeCallbacks.add(callback);
  static void removeListener(VoidCallback callback) => _onChangeCallbacks.remove(callback);
  static void _notifyListeners() {
    for (final cb in _onChangeCallbacks) {
      try { cb(); } catch (_) {}
    }
  }

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/.knot_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final json = content.replaceAll('{', '{"').replaceAll('}', '"}').replaceAll(': ', ':').replaceAll(', ', ',');
          final Map<String, dynamic> parsed = {};
          final entryPattern = RegExp(r'"([^"]+)":([^,}]+)');
          for (final match in entryPattern.allMatches(content)) {
            final key = match.group(1)!;
            final val = match.group(2)!.trim();
            if (val == 'true') {
              parsed[key] = true;
            } else if (val == 'false') {
              parsed[key] = false;
            } else if (val.contains('.')) {
              parsed[key] = double.tryParse(val) ?? val;
            } else {
              parsed[key] = int.tryParse(val) ?? val;
            }
          }
          _settings = AppSettings.fromJson(parsed);
        }
      }
    } catch (e) {
      // Use defaults
    }
    _loaded = true;
  }

  static Future<void> save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/.knot_settings.json');
      final json = _settings.toJson();
      final buffer = StringBuffer('{');
      var first = true;
      json.forEach((key, value) {
        if (!first) buffer.write(',');
        first = false;
        if (value is String) {
          buffer.write('"$key":"$value"');
        } else {
          buffer.write('"$key":$value');
        }
      });
      buffer.write('}');
      await file.writeAsString(buffer.toString());
    } catch (e) {
      // Ignore save errors
    }
  }

  static void update(void Function(AppSettings) updateFn) {
    updateFn(_settings);
    save();
    _notifyListeners();
  }
}