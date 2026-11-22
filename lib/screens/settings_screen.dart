import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = SettingsService.settings;

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00d4ff)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings', style: TextStyle(color: Color(0xFF00d4ff))),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _deviceModeSection(s),
          const SizedBox(height: 32),
          if (!s.lowEndDevice) ...[
            _sectionHeader('Graph Visuals'),
          const SizedBox(height: 16),
          _sliderTile(
            'Node Glow',
            s.nodeGlowIntensity,
            0,
            100,
            (v) => SettingsService.update((s) => s.nodeGlowIntensity = v),
            '${s.nodeGlowIntensity.toInt()}%',
            const Color(0xFF00d4ff),
          ),
          _sliderTile(
            'Node Size',
            s.nodeSize,
            0.5,
            2.0,
            (v) => SettingsService.update((s) => s.nodeSize = v),
            '${(s.nodeSize * 100).toInt()}%',
            const Color(0xFF00d4ff),
          ),
          _sliderTile(
            'Edge Thickness',
            s.edgeThickness,
            0.5,
            3.0,
            (v) => SettingsService.update((s) => s.edgeThickness = v),
            '${(s.edgeThickness).toStringAsFixed(1)}x',
            const Color(0xFF7b2cbf),
          ),
          _sliderTile(
            'Edge Glow',
            s.edgeGlow,
            0,
            100,
            (v) => SettingsService.update((s) => s.edgeGlow = v),
            '${s.edgeGlow.toInt()}%',
            const Color(0xFF00ff88),
          ),
          _switchTile(
            'Show Edges',
            s.showEdges,
            (v) => SettingsService.update((s) => s.showEdges = v),
            const Color(0xFF00d4ff),
          ),
          _switchTile(
            'Floating Animation',
            s.floatingAnimation,
            (v) => SettingsService.update((s) => s.floatingAnimation = v),
            const Color(0xFF7b2cbf),
          ),
          const SizedBox(height: 32),
          _sectionHeader('Text & Labels'),
          const SizedBox(height: 16),
          _sliderTile(
            'Graph Label Size',
            s.labelSize,
            0.5,
            2.0,
            (v) => SettingsService.update((s) => s.labelSize = v),
            '${(s.labelSize * 100).toInt()}%',
            const Color(0xFF00d4ff),
          ),
          _sliderTile(
            'Editor Text Size',
            s.editorTextSize,
            0.5,
            2.0,
            (v) => SettingsService.update((s) => s.editorTextSize = v),
            '${(s.editorTextSize * 100).toInt()}%',
            const Color(0xFF00d4ff),
          ),
          const SizedBox(height: 32),
          _sectionHeader('Behavior'),
          const SizedBox(height: 16),
          _switchTile(
            'Confirm Before Delete',
            s.confirmBeforeDelete,
            (v) => SettingsService.update((s) => s.confirmBeforeDelete = v),
            const Color(0xFFff006e),
          ),
          const SizedBox(height: 32),
          _sectionHeader('Accent Color'),
          const SizedBox(height: 16),
          _colorPicker(s.accentColorIndex),
          ],
          if (s.lowEndDevice) ...[
            _sectionHeader('Performance Mode'),
            const SizedBox(height: 16),
            _infoCard(),
          ],
          const SizedBox(height: 32),
          _syncServerSection(s),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _syncServerSection(AppSettings s) {
    final ctrl = TextEditingController(text: s.syncServerUrl);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: s.syncEnabled ? const Color(0xFF00ff88) : const Color(0xFF2d2d44),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_sync, color: Color(0xFF00d4ff), size: 20),
              const SizedBox(width: 8),
              Text(
                'Sync Server',
                style: const TextStyle(
                  color: Color(0xFF00d4ff),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Switch(
                value: s.syncEnabled,
                activeColor: const Color(0xFF00ff88),
                onChanged: (v) {
                  SettingsService.update((s) => s.syncEnabled = v);
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => SettingsService.update((s) => s.syncServerUrl = v),
            decoration: InputDecoration(
              hintText: 'http://100.81.91.113:8080',
              hintStyle: TextStyle(color: Colors.grey[600]),
              labelText: 'Server URL',
              labelStyle: TextStyle(color: Colors.grey[500]),
              filled: true,
              fillColor: const Color(0xFF2d2d44),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: s.syncEnabled ? _pingServer : null,
                  icon: const Icon(Icons.wifi, size: 18),
                  label: const Text('Ping Server'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00d4ff),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: s.syncEnabled ? _syncNow : null,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Sync Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7b2cbf),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.syncServerUrl.isEmpty
                ? 'Enter your Tailscale server IP (e.g. http://100.81.91.113:8080) and enable sync.'
                : 'Server: ${s.syncServerUrl}',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _pingServer() async {
    final ok = await SyncService.instance.ping();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Server reachable!' : 'Cannot reach server'),
          backgroundColor: ok ? const Color(0xFF00ff88) : const Color(0xFFff006e),
        ),
      );
    }
  }

  Future<void> _syncNow() async {
    if (!SettingsService.settings.syncEnabled) return;
    if (!SettingsService.settings.syncServerUrl.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a server URL first'),
          backgroundColor: Color(0xFFff006e),
        ),
      );
      return;
    }
    _showSyncProgressSheet();
    await SyncService.instance.sync();
    if (mounted) Navigator.pop(context);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync complete'),
          backgroundColor: Color(0xFF00ff88),
        ),
      );
    }
  }

  void _showSyncProgressSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return ValueListenableBuilder<double>(
            valueListenable: SyncService.syncProgressNotifier,
            builder: (_, progress, __) {
              return ValueListenableBuilder<String>(
                valueListenable: SyncService.syncStatusNotifier,
                builder: (_, status, __) {
                  return ValueListenableBuilder<List<String>>(
                    valueListenable: SyncService.syncLogNotifier,
                    builder: (_, logs, __) {
                      final pct = (progress * 100).toInt().clamp(0, 100);
                      return Container(
                        padding: const EdgeInsets.all(20),
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.cloud_sync, color: Color(0xFF00d4ff), size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Syncing…',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$pct%',
                                  style: const TextStyle(
                                    color: Color(0xFF00ff88),
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2d2d44),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.transparent,
                                  color: const Color(0xFF00d4ff),
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              status,
                              style: const TextStyle(
                                color: Color(0xFFe0e0e0),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: ListView.builder(
                                itemCount: logs.length,
                                itemBuilder: (_, i) {
                                  final line = logs[i];
                                  final isError = line.contains('error') || line.contains('failed');
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 1),
                                    child: Text(
                                      line,
                                      style: TextStyle(
                                        color: isError ? const Color(0xFFff006e) : Colors.grey[400],
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text(
                                  'Close',
                                  style: TextStyle(color: Color(0xFF00d4ff)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _deviceModeSection(AppSettings s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: s.lowEndDevice ? const Color(0xFFff006e) : const Color(0xFF00d4ff),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.memory,
                color: s.lowEndDevice ? const Color(0xFFff006e) : const Color(0xFF00d4ff),
              ),
              const SizedBox(width: 8),
              Text(
                'Device Mode',
                style: TextStyle(
                  color: s.lowEndDevice ? const Color(0xFFff006e) : const Color(0xFF00d4ff),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    SettingsService.update((s) {
                      s.lowEndDevice = true;
                      s.nodeGlowIntensity = 0;
                      s.edgeGlow = 0;
                      s.floatingAnimation = true;
                    });
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: s.lowEndDevice ? const Color(0xFFff006e) : const Color(0xFF2d2d44),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        'Low End',
                        style: TextStyle(
                          color: s.lowEndDevice ? Colors.white : Colors.grey[400],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    SettingsService.update((s) {
                      s.lowEndDevice = false;
                      s.nodeGlowIntensity = 50;
                      s.edgeGlow = 30;
                      s.floatingAnimation = true;
                    });
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !s.lowEndDevice ? const Color(0xFF00d4ff) : const Color(0xFF2d2d44),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        'High End',
                        style: TextStyle(
                          color: !s.lowEndDevice ? Colors.white : Colors.grey[400],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.lowEndDevice
                ? 'Optimized: No glows, efficient physics, smooth on any device'
                : 'Full render: Glows, animations, all the fancy stuff',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2d2d44),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF00ff88), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Performance mode active - graph will run smooth on low-end devices',
              style: TextStyle(color: Colors.grey[300], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF00d4ff),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _sliderTile(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged,
    String display,
    Color activeColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2d2d44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFFe0e0e0))),
              Text(display, style: TextStyle(color: activeColor, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: activeColor,
              inactiveTrackColor: const Color(0xFF2d2d44),
              thumbColor: activeColor,
              overlayColor: activeColor.withOpacity(0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: (v) {
                onChanged(v);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(
    String label,
    bool value,
    Function(bool) onChanged,
    Color activeColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2d2d44)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFe0e0e0))),
          Switch(
            value: value,
            activeColor: activeColor,
            onChanged: (v) {
              onChanged(v);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

Widget _colorPicker(int selectedIndex) {
    final colors = const [
      Color(0xFF00d4ff),
      Color(0xFFff006e),
      Color(0xFF7b2cbf),
      Color(0xFF00ff88),
    ];
    final labels = const ['Cyan', 'Magenta', 'Purple', 'Green'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2d2d44)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(colors.length, (i) {
          final isSelected = i == selectedIndex;
          final color = colors[i];
          return Column(
            children: [
              GestureDetector(
                onTap: () {
                  SettingsService.update((s) => s.accentColorIndex = i);
                  setState(() {});
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 12)]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 24)
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[i],
                style: TextStyle(
                  color: isSelected ? color : Colors.grey[600],
                  fontSize: 10,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}