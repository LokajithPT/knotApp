import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io';
import 'dart:collection';
import 'package:audioplayers/audioplayers.dart';
import '../models/note.dart';
import '../services/knot_service.dart';
import '../services/settings_service.dart';
import '../widgets/voice_recording_dialog.dart';
import 'note_detail_screen.dart';

class GraphScreen extends StatefulWidget {
  final Project project;
  final String? highlightNote;

  const GraphScreen({super.key, required this.project, this.highlightNote});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> with TickerProviderStateMixin {
  late List<_NodeData> nodes;
  late List<_EdgeData> edges;
  late AnimationController _controller;
  bool _isSettled = false;
  int? _draggedNode;
  String? _selectedNode;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _isDraggingToTrash = false;
  String _searchQuery = '';
  Note? _previewNote;
  String? _highlightedNode;
  bool _showHighlightDialog = false;
  double _highlightPulse = 0.0;
  bool _pulsingHighlight = false;
  double _lastNodeGlow = 0;
  double _lastNodeSize = 1;
  double _lastEdgeGlow = 0;
  double _lastEdgeThickness = 1;
  double _lastLabelSize = 1;
  bool _showMinimap = false;
  int? _selectedStaticNode;
  bool _globalStaticMode = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _controller.addListener(_updatePhysics);
    _highlightedNode = widget.highlightNote;
    _captureInitialSettings();
    _globalStaticMode = SettingsService.settings.globalStaticMode;
    SettingsService.addListener(_onSettingsChanged);
  }

  void _captureInitialSettings() {
    final s = SettingsService.settings;
    _lastNodeGlow = s.nodeGlowIntensity;
    _lastNodeSize = s.nodeSize;
    _lastEdgeGlow = s.edgeGlow;
    _lastEdgeThickness = s.edgeThickness;
    _lastLabelSize = s.labelSize;
  }

  void _onSettingsChanged() {
    final s = SettingsService.settings;
    bool needsRebuild = false;
    if (s.nodeGlowIntensity != _lastNodeGlow || s.nodeSize != _lastNodeSize || 
        s.edgeGlow != _lastEdgeGlow || s.edgeThickness != _lastEdgeThickness || 
        s.labelSize != _lastLabelSize) {
      _lastNodeGlow = s.nodeGlowIntensity;
      _lastNodeSize = s.nodeSize;
      _lastEdgeGlow = s.edgeGlow;
      _lastEdgeThickness = s.edgeThickness;
      _lastLabelSize = s.labelSize;
      needsRebuild = true;
    }
    if (s.floatingAnimation != _lastFloatingAnimation) {
      _lastFloatingAnimation = s.floatingAnimation;
      needsRebuild = true;
    }
    if (needsRebuild && mounted) setState(() {});
  }

  bool _lastFloatingAnimation = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshGraph();
    if (widget.highlightNote != null && !_showHighlightDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showHighlightDialogForNote(widget.highlightNote!));
    }
  }

  void _showHighlightDialogForNote(String noteName) async {
    final proj = await KnotService.loadProject(widget.project.name);
    final exists = proj.notes.any((n) => n.name == noteName);
    
    if (!mounted) return;
    
    setState(() {
      _showHighlightDialog = true;
      _highlightedNode = noteName;
      _pulsingHighlight = true;
      _highlightPulse = 0.0;
    });
    
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _pulsingHighlight = false);
    });
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Note: $noteName', style: const TextStyle(color: Color(0xFFff006e))),
        content: Text(
          exists ? 'This note exists in the graph. Tap "Open" to view it, or "Go Back" to stay on this graph.' : 'Note not found in this project.',
          style: const TextStyle(color: Color(0xFFe0e0e0)),
        ),
        actions: [
          if (exists)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final allNotes = await KnotService.loadProject(widget.project.name);
                final note = allNotes.notes.firstWhere((n) => n.name == noteName);
                await _saveNodePositions();
                if (mounted) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note, filePath: note.filePath, project: widget.project)));
                  if (mounted) {
                    final savedPositions = await KnotService.loadNodePositions(widget.project.name);
                    for (final node in nodes) {
                      final pos = savedPositions?[node.id];
                      if (pos != null) {
                        node.x = pos['x']!;
                        node.y = pos['y']!;
                        node.targetX = pos['x'];
                        node.targetY = pos['y'];
                        node.vx = 0;
                        node.vy = 0;
                      }
                    }
                    setState(() {});
                  }
                }
              },
              child: const Text('Open', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () { Navigator.pop(ctx); setState(() => _highlightedNode = null); },
            child: Text('Stay on Graph', style: TextStyle(color: Colors.grey[500])),
          ),
        ],
      ),
    );
  }

  void _initGraph() {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final padding = 180.0;
    
    // Scatter layout - fully random spread far apart
    nodes = widget.project.notes.asMap().entries.map((e) {
      return _NodeData(
        id: e.value.name,
        x: padding + math.Random().nextDouble() * (w - padding * 2),
        y: padding + math.Random().nextDouble() * (h - padding * 2),
        vx: 0,
        vy: 0,
        isVoice: e.value.isVoiceNote,
      );
    }).toList();

    final externalProjects = <String>{};
    edges = widget.project.links.map((link) {
      final sourceIndex = nodes.indexWhere((n) => n.id == link.source);
      if (link.isInterProject) {
        externalProjects.add(link.interProject!);
        if (sourceIndex >= 0) return _EdgeData(source: sourceIndex, target: -1, isInterProject: true, interProject: link.interProject);
      } else {
        final targetIndex = nodes.indexWhere((n) => n.id == link.target);
        if (sourceIndex >= 0 && targetIndex >= 0) return _EdgeData(source: sourceIndex, target: targetIndex);
      }
      return null;
    }).whereType<_EdgeData>().toList();

    int extIndex = nodes.length;
    for (final proj in externalProjects) {
      nodes.add(_NodeData(
        id: proj,
        x: math.Random().nextDouble() * 200 + 100,
        y: math.Random().nextDouble() * 200 + 100,
        vx: 0,
        vy: 0,
        isExternal: true,
      ));
      for (int i = 0; i < edges.length; i++) {
        if (edges[i].isInterProject && edges[i].interProject == proj) {
          edges[i] = _EdgeData(source: edges[i].source, target: extIndex, isInterProject: true, interProject: proj);
        }
      }
      extIndex++;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    SettingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  bool _isPanning = false;
  Offset _lastPanPosition = Offset.zero;

  void _onScaleStart(ScaleStartDetails details) {
    _draggedNode = null;
    _isSettled = false;
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
    if (details.pointerCount == 1) {
      final scaleOffset = Offset(_offset.dx / _scale, _offset.dy / _scale);
      final pos = (details.localFocalPoint - scaleOffset) / _scale;
      for (var i = 0; i < nodes.length; i++) {
        final dx = nodes[i].x - pos.dx;
        final dy = nodes[i].y - pos.dy;
        if (math.sqrt(dx * dx + dy * dy) < 50) {
          if (!nodes[i].isStatic) {
            _draggedNode = i;
            nodes[i].targetX = null;
            nodes[i].targetY = null;
          }
          break;
        }
      }
      if (_draggedNode == null) {
        _isPanning = true;
        _lastPanPosition = details.localFocalPoint;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_draggedNode != null) {
      final scaleOffset = Offset(_offset.dx / _scale, _offset.dy / _scale);
      final pos = (details.localFocalPoint - scaleOffset) / _scale;
      nodes[_draggedNode!].x = pos.dx;
      nodes[_draggedNode!].y = pos.dy;
      final screenHeight = MediaQuery.of(context).size.height;
      final isInTrashZone = pos.dy > screenHeight - 120;
      if (isInTrashZone != _isDraggingToTrash) {
        setState(() { _isDraggingToTrash = isInTrashZone; });
      }
    } else if (_isPanning) {
      final delta = details.localFocalPoint - _lastPanPosition;
      setState(() {
        _offset = Offset(_offset.dx + delta.dx, _offset.dy + delta.dy);
      });
      _lastPanPosition = details.localFocalPoint;
    } else if (details.pointerCount >= 2) {
      final oldScale = _scale;
      final scaleFactor = details.scale;
      final newScale = (oldScale * (1 + (scaleFactor - 1) * 0.3)).clamp(0.3, 3.0);
      
      final focalPoint = details.localFocalPoint;
      final worldFocalPoint = (focalPoint - _offset) / oldScale;
      
      final newOffset = focalPoint - worldFocalPoint * newScale;
      
      setState(() {
        _scale = newScale;
        _offset = newOffset;
      });
    }
  }

  void _recenter() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  Future<void> _saveNodePositions() async {
    final positions = <String, Map<String, double>>{};
    final staticNodes = <String, bool>{};
    for (final node in nodes) {
      if (!node.isExternal) {
        positions[node.id] = {'x': node.x, 'y': node.y};
        if (node.isStatic) staticNodes[node.id] = true;
      }
    }
    await KnotService.saveNodePositions(widget.project.name, positions, staticNodes: staticNodes);
  }

  void _onScaleEnd(ScaleEndDetails details) async {
    _isPanning = false;
    if (_draggedNode != null && _isDraggingToTrash) {
      final node = nodes[_draggedNode!];
      if (!node.isExternal) {
        bool shouldDelete = true;
        if (SettingsService.settings.confirmBeforeDelete) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              backgroundColor: const Color(0xFF1a1a2e),
              title: const Text('Delete?', style: TextStyle(color: Color(0xFFff006e))),
              content: Text('Delete "${node.id}"?', style: const TextStyle(color: Color(0xFFe0e0e0))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFff006e)))),
              ],
            ),
          );
          shouldDelete = confirm ?? false;
        }
        if (shouldDelete) {
          final projectDir = Directory(widget.project.path);
          await for (final entity in projectDir.list()) {
            if (entity is File) {
              final fileName = entity.path.split('/').last;
              final nameWithoutExt = fileName.contains('.') ? fileName.split('.').first : fileName;
              if (nameWithoutExt == node.id || fileName.startsWith(node.id)) {
                try {
                  await entity.delete();
                } catch (e) {
                  // ignore
                }
              }
            }
          }
          _refreshGraph();
        }
      }
    }
    _draggedNode = null;
    _isDraggingToTrash = false;
    await _saveNodePositions();
  }

  double _time = 0;

  void _updatePhysics() {
    if (nodes.isEmpty) return;
    _time += 0.016;

    if (_pulsingHighlight && _highlightedNode != null) {
      _highlightPulse = (math.sin(_time * 8) + 1) / 2;
    }

    final centerX = MediaQuery.of(context).size.width / 2 / _scale;
    final centerY = MediaQuery.of(context).size.height / 2 / _scale;

    // Global static mode: skip forces but allow target movement (for layouts)
    if (_globalStaticMode) {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].targetX != null && !nodes[i].isStatic) {
          final dx = nodes[i].targetX! - nodes[i].x;
          final dy = nodes[i].targetY! - nodes[i].y;
          nodes[i].vx += dx * 0.08;
          nodes[i].vy += dy * 0.08;
          nodes[i].vx *= 0.85;
          nodes[i].vy *= 0.85;
          nodes[i].x += nodes[i].vx;
          nodes[i].y += nodes[i].vy;
        }
      }
      _time += 0.016;
      setState(() {});
      return;
    }

    // Check if already settled - skip physics but still update time for voice ripples
    final isLowEnd = SettingsService.settings.lowEndDevice;
    if (_isSettled && _draggedNode == null && !_pulsingHighlight) {
      if (isLowEnd) {
        return; // Full stop - no animation
      }
      _time += 0.016;
      setState(() {}); // Still repaint to keep voice ripples animating
      return;
    }

    // On low-end, run physics less frequently (every 3rd frame)
    if (isLowEnd && (_time * 60).toInt() % 3 != 0) {
      return;
    }

    double totalVelocity = 0;

    // Gentle floating with occasional bob - playful movement
    if (SettingsService.settings.floatingAnimation) {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].targetX != null || nodes[i].isStatic) continue;
        
        final floatX = math.sin(_time * 0.15 + i * 0.5) * 2.0;
        final floatY = math.cos(_time * 0.12 + i * 0.4) * 2.0;

        final dxCenter = (centerX + floatX) - nodes[i].x;
        final dyCenter = (centerY + floatY) - nodes[i].y;
        nodes[i].vx += dxCenter * 0.0008;
        nodes[i].vy += dyCenter * 0.0008;
      }
    }

    // Soft repulsion - cushiony, not rigid
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].isStatic) continue;
      for (var j = i + 1; j < nodes.length; j++) {
        if (nodes[j].isStatic) continue;
        final dx = nodes[j].x - nodes[i].x;
        final dy = nodes[j].y - nodes[i].y;
        final dist = math.sqrt(dx * dx + dy * dy);
        final minDist = 80.0;
        if (dist > 0 && dist < 400) {
          double repulsion = 1500.0 / (dist * dist + 50);
          final nx = dx / dist;
          final ny = dy / dist;
          nodes[i].vx -= nx * repulsion * 0.02;
          nodes[i].vy -= ny * repulsion * 0.02;
          nodes[j].vx += nx * repulsion * 0.02;
          nodes[j].vy += ny * repulsion * 0.02;
        }
        if (dist > 0 && dist < minDist + 15) {
          final overlap = (minDist + 15) - dist;
          final nx = dx / dist;
          final ny = dy / dist;
          nodes[i].x -= nx * overlap * 0.3;
          nodes[i].y -= ny * overlap * 0.3;
          nodes[j].x += nx * overlap * 0.3;
          nodes[j].y += ny * overlap * 0.3;
        }
      }
    }

    for (final edge in edges) {
      if (edge.target < 0 || edge.target >= nodes.length) continue;
      
      final sourceNode = nodes[edge.source];
      final targetNode = nodes[edge.target];
      
      if (sourceNode.targetX != null && targetNode.targetX != null) continue;
      if (sourceNode.isStatic || targetNode.isStatic) continue;
      
      final dx = targetNode.x - sourceNode.x;
      final dy = targetNode.y - sourceNode.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist > 0) {
        final force = (dist - 100) * 0.004;
        final fx = dx / dist * force;
        final fy = dy / dist * force;
        nodes[edge.source].vx += fx * 0.5;
        nodes[edge.source].vy += fy * 0.5;
        nodes[edge.target].vx -= fx * 0.5;
        nodes[edge.target].vy -= fy * 0.5;
      }
    }

    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].isStatic) continue;
      if (nodes[i].targetX != null) {
        final dx = nodes[i].targetX! - nodes[i].x;
        final dy = nodes[i].targetY! - nodes[i].y;
        nodes[i].vx += dx * 0.08;
        nodes[i].vy += dy * 0.08;
        nodes[i].vx *= 0.85;
        nodes[i].vy *= 0.85;
        nodes[i].x += nodes[i].vx;
        nodes[i].y += nodes[i].vy;
      } else {
        nodes[i].vx *= 0.96;
        nodes[i].vy *= 0.96;
        nodes[i].x += nodes[i].vx;
        nodes[i].y += nodes[i].vy;
      }
      totalVelocity += nodes[i].vx.abs() + nodes[i].vy.abs();
    }

    // Mark as settled when velocities are negligible
    if (totalVelocity < 0.5 && _draggedNode == null) {
      _isSettled = true;
    } else {
      _isSettled = false;
    }

    setState(() {});
  }

  void _onTapUp(TapUpDetails details) async {
    final scaleOffset = Offset(_offset.dx / _scale, _offset.dy / _scale);
    final pos = (details.localPosition - scaleOffset) / _scale;
    for (var i = 0; i < nodes.length; i++) {
      final dx = nodes[i].x - pos.dx;
      final dy = nodes[i].y - pos.dy;
      if (math.sqrt(dx * dx + dy * dy) < 50) {
        if (nodes[i].isExternal) {
          final proj = await KnotService.loadProject(nodes[i].id);
          if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => GraphScreen(project: proj)));
        } else {
          // Load fresh note from disk to get correct type
          final allNotes = await KnotService.loadProject(widget.project.name);
          final freshNote = allNotes.notes.firstWhere(
            (n) => n.name == nodes[i].id,
            orElse: () => Note(
              name: nodes[i].id, 
              content: '', 
              preview: '', 
              tags: [], 
              type: nodes[i].isVoice ? 'voice' : 'note',
              filePath: nodes[i].isVoice ? '${widget.project.path}/${nodes[i].id}.m4a' : '${widget.project.path}/${nodes[i].id}.md',
            ),
          );
          await _saveNodePositions();
          await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteDetailScreen(note: freshNote, filePath: freshNote.filePath, project: widget.project)));
          if (mounted) {
            final savedPositions = await KnotService.loadNodePositions(widget.project.name);
            for (final node in nodes) {
              final pos = savedPositions?[node.id];
              if (pos != null) {
                node.x = pos['x']!;
                node.y = pos['y']!;
                node.targetX = pos['x'];
                node.targetY = pos['y'];
                node.vx = 0;
                node.vy = 0;
              }
            }
            setState(() {});
          }
        }
        break;
      }
    }
  }

  Future<void> _createNewNote() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Note', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.note_add, color: Color(0xFF00d4ff)),
              title: const Text('Text Note', style: TextStyle(color: Color(0xFFe0e0e0))),
              subtitle: const Text('Markdown note', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'text'),
            ),
            ListTile(
              leading: const Icon(Icons.mic, color: Color(0xFF00ff88)),
              title: const Text('Voice Note', style: TextStyle(color: Color(0xFFe0e0e0))),
              subtitle: const Text('Audio recording', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'voice'),
            ),
          ],
        ),
      ),
    );

    if (choice == 'text') {
      await _createTextNote();
    } else if (choice == 'voice') {
      await _createVoiceNote();
    }
  }

  Future<void> _createTextNote() async {
    final controller = TextEditingController();
    final noteName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Note', style: TextStyle(color: Color(0xFF00d4ff))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Note name',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00d4ff))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Create', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (noteName != null && noteName.isNotEmpty) {
      final note = Note(name: noteName, content: '# $noteName\n\n', preview: '', tags: []);
      final filePath = '${widget.project.path}/$noteName.md';
      await File(filePath).writeAsString(note.content);
      await _saveNodePositions();
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note, filePath: filePath, project: widget.project)));
        await Future.delayed(const Duration(milliseconds: 100));
        _refreshGraph();
      }
    }
  }

  Future<void> _createVoiceNote() async {
    final controller = TextEditingController();
    final noteName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Voice Note', style: TextStyle(color: Color(0xFF00ff88))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Note name',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ff88))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Record', style: TextStyle(color: Color(0xFF00ff88), fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (noteName != null && noteName.isNotEmpty) {
      final filePath = '${widget.project.path}/$noteName.m4a';
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => VoiceRecordingDialog(
            filePath: filePath,
            noteName: noteName,
            onComplete: () async {
              await Future.delayed(const Duration(milliseconds: 100));
              _refreshGraph();
            },
          ),
        );
      }
    }
  }

  void _unpinNode() {
    if (_selectedStaticNode != null) {
      setState(() {
        nodes[_selectedStaticNode!].isStatic = false;
        _selectedStaticNode = null;
      });
      _saveNodePositions();
    }
  }

  void _unpinAll() {
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].isStatic = false;
    }
    setState(() {
      _selectedStaticNode = null;
    });
    _saveNodePositions();
  }

  void _showSearch() {
    final controller = TextEditingController(text: _searchQuery);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Search Notes', style: TextStyle(color: Color(0xFF00d4ff))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search...',
            hintStyle: TextStyle(color: Colors.grey[600]),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF00d4ff)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00d4ff))),
          ),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        actions: [
          TextButton(onPressed: () { setState(() => _searchQuery = ''); Navigator.pop(ctx); }, child: Text('Clear', style: TextStyle(color: Colors.grey[500]))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done', style: TextStyle(color: Color(0xFF00d4ff)))),
        ],
      ),
    );
  }

  Future<void> _showNotePreview(Offset position) async {
    final scaleOffset = Offset(_offset.dx / _scale, _offset.dy / _scale);
    final pos = (position - scaleOffset) / _scale;
    
    for (var i = 0; i < nodes.length; i++) {
      final dx = nodes[i].x - pos.dx;
      final dy = nodes[i].y - pos.dy;
      if (math.sqrt(dx * dx + dy * dy) < 50) {
        if (nodes[i].isExternal) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1a1a2e),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.folder, color: Color(0xFF9d4edd), size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(nodes[i].id, style: const TextStyle(color: Color(0xFF9d4edd)))),
                ],
              ),
              content: Text('Open project "${nodes[i].id}"?', style: const TextStyle(color: Color(0xFFe0e0e0))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final proj = await KnotService.loadProject(nodes[i].id);
                    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => GraphScreen(project: proj)));
                  },
                  child: const Text('Open', style: TextStyle(color: Color(0xFF9d4edd), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          break;
        }
        // Load fresh note from disk
        final freshProject = await KnotService.loadProject(widget.project.name);
        final note = freshProject.notes.firstWhere((n) => n.name == nodes[i].id, orElse: () => Note(name: nodes[i].id, content: '', preview: '', tags: []));
        setState(() => _previewNote = note);
        
        final backlinks = freshProject.links.where((l) => l.target == nodes[i].id).map((l) => l.source).toList();
        final forwardLinks = <String>[];
        final linkPattern = RegExp(r'\[\[([^\]]+)\]\]');
        for (final match in linkPattern.allMatches(note.content)) {
          forwardLinks.add(match.group(1)!);
        }
        
        showDialog(
          context: context,
          builder: (ctx) => _NotePreviewDialog(
            note: note,
            isVoice: nodes[i].isVoice,
            isStatic: nodes[i].isStatic,
            backlinks: backlinks,
            forwardLinks: forwardLinks,
            onPin: () {
              Navigator.pop(ctx);
              setState(() {
                _selectedStaticNode = i;
                nodes[i].isStatic = true;
              });
            },
            onUnpin: () {
              Navigator.pop(ctx);
              setState(() {
                _selectedStaticNode = null;
                nodes[i].isStatic = false;
              });
            },
            onDelete: () async {
              Navigator.pop(ctx);
              bool shouldDelete = true;
              if (SettingsService.settings.confirmBeforeDelete) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: const Color(0xFF1a1a2e),
                    title: const Text('Delete?', style: TextStyle(color: Color(0xFFff006e))),
                    content: Text('Delete "${note.name}"?', style: const TextStyle(color: Color(0xFFe0e0e0))),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFff006e)))),
                    ],
                  ),
                );
                shouldDelete = confirm ?? false;
              }
              if (shouldDelete) {
                final projectDir = Directory(widget.project.path);
                await for (final entity in projectDir.list()) {
                  if (entity is File) {
                    final fileName = entity.path.split('/').last;
                    final nameWithoutExt = fileName.contains('.') ? fileName.split('.').first : fileName;
                    if (nameWithoutExt == note.name || fileName.startsWith(note.name)) {
                      try {
                        await entity.delete();
                      } catch (e) {
                        // ignore delete errors
                      }
                    }
                  }
                }
                if (mounted) {
                  _refreshGraph();
                }
              }
            },
          ),
        );
        break;
      }
    }
  }

  void _showOrganizeMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Organize', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.account_tree, color: Color(0xFF00d4ff)),
              title: const Text('Tree Layout', style: TextStyle(color: Color(0xFFe0e0e0))),
              subtitle: const Text('Graph with head nodes', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              onTap: () { Navigator.pop(ctx); _organizeTreeGraph(); },
            ),
            ListTile(
              leading: const Icon(Icons.scatter_plot, color: Color(0xFF7b2cbf)),
              title: const Text('Scatter', style: TextStyle(color: Color(0xFFe0e0e0))),
              subtitle: const Text('Random spread', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              onTap: () { Navigator.pop(ctx); _organizeScatter(); },
            ),
            ListTile(
              leading: const Icon(Icons.circle_outlined, color: Color(0xFF00ff88)),
              title: const Text('Circular', style: TextStyle(color: Color(0xFFe0e0e0))),
              subtitle: const Text('Ring of nodes', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              onTap: () { Navigator.pop(ctx); _organizeCircular(); },
            ),
            ListTile(
              leading: const Icon(Icons.grid_view, color: Color(0xFFff006e)),
              title: const Text('Grid', style: TextStyle(color: Color(0xFFe0e0e0))),
              subtitle: const Text('Rows and columns', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              onTap: () { Navigator.pop(ctx); _organizeGrid(); },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline, color: Color(0xFF9d4edd)),
              title: const Text('Star', style: TextStyle(color: Color(0xFFe0e0e0))),
              subtitle: const Text('Center with satellites', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              onTap: () { Navigator.pop(ctx); _organizeStar(); },
            ),
            ListTile(
              leading: const Icon(Icons.clear, color: Color(0xFFff006e)),
              title: const Text('Unpin All', style: TextStyle(color: Color(0xFFff006e))),
              subtitle: const Text('Remove all pins', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
              onTap: () { Navigator.pop(ctx); _unpinAll(); },
            ),
          ],
        ),
      ),
    );
  }

  void _organizeTreeGraph() {
    if (nodes.isEmpty) return;
    _isSettled = false;
    if (!_controller.isAnimating) _controller.repeat();

    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final centerX = width / 2 / _scale;
    final centerY = height / 2 / _scale;

    final adjacency = <int, List<int>>{};
    for (final edge in edges) {
      adjacency.putIfAbsent(edge.source, () => []).add(edge.target);
    }

    final inDegree = <int, int>{};
    for (final edge in edges) {
      inDegree[edge.target] = (inDegree[edge.target] ?? 0) + 1;
    }

    final roots = <int>[];
    for (int i = 0; i < nodes.length; i++) {
      if ((inDegree[i] ?? 0) == 0) roots.add(i);
    }

    if (roots.isEmpty) roots.add(0);

    final visited = <int>{};
    final depthMap = <int, int>{};
    
    int getDepth(int node) {
      if (depthMap.containsKey(node)) return depthMap[node]!;
      final children = adjacency[node] ?? [];
      if (children.isEmpty) {
        depthMap[node] = 0;
        return 0;
      }
      int maxChildDepth = 0;
      for (final child in children) {
        final d = getDepth(child);
        if (d > maxChildDepth) maxChildDepth = d;
      }
      depthMap[node] = maxChildDepth + 1;
      return maxChildDepth + 1;
    }
    
    for (int i = 0; i < nodes.length; i++) {
      getDepth(i);
    }
    
    int maxDepth = 0;
    for (final d in depthMap.values) {
      if (d > maxDepth) maxDepth = d;
    }
    
    final levelSpacing = 125.0;
    final vertGap = 150.0;
    
    final byLevel = <int, List<int>>{};
    for (int i = 0; i < nodes.length; i++) {
      final depth = depthMap[i] ?? 0;
      byLevel.putIfAbsent(depth, () => []).add(i);
    }
    
    void placeLevel(int depth, double startY) {
      final nodesAtLevel = byLevel[depth] ?? [];
      if (nodesAtLevel.isEmpty) return;
      
      final totalWidth = (nodesAtLevel.length - 1) * levelSpacing;
      final startX = centerX - totalWidth / 2;
      
      for (int i = 0; i < nodesAtLevel.length; i++) {
        final node = nodesAtLevel[i];
        visited.add(node);
        nodes[node].targetX = startX + i * levelSpacing;
        nodes[node].targetY = startY;
      }
      
      final children = <int>{};
      for (final node in nodesAtLevel) {
        children.addAll(adjacency[node] ?? []);
      }
      if (children.isNotEmpty) {
        final nextDepth = depth + 1;
        byLevel[nextDepth] = byLevel.putIfAbsent(nextDepth, () => []);
        for (final c in children) {
          if (!byLevel[nextDepth]!.contains(c)) {
            byLevel[nextDepth]!.add(c);
          }
        }
      }
    }
    
    final startY = centerY - (maxDepth * vertGap) / 2;
    for (int d = 0; d <= maxDepth; d++) {
      placeLevel(d, startY + d * vertGap);
    }
    
    for (int i = 0; i < nodes.length; i++) {
      if (!visited.contains(i)) {
        nodes[i].targetX = centerX + (math.Random().nextDouble() - 0.5) * 300;
        nodes[i].targetY = centerY + (math.Random().nextDouble() - 0.5) * 300;
      }
    }
  }

  void _organizeScatter() {
    if (nodes.isEmpty) return;
    _isSettled = false;
    if (!_controller.isAnimating) _controller.repeat();
    
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final padding = 120.0;
    
    final spacing = 120.0;
    final cols = ((w - padding * 2) / spacing).floor();
    final rows = ((h - padding * 2) / spacing).floor();
    final totalSlots = cols * rows;
    
    final positions = <double>[];
    for (double y = padding; y < h - padding; y += spacing) {
      for (double x = padding; x < w - padding; x += spacing) {
        positions.add(x);
        positions.add(y);
      }
    }
    
    positions.shuffle();
    
    for (int i = 0; i < nodes.length; i++) {
      if (i * 2 < positions.length) {
        nodes[i].targetX = positions[i * 2];
        nodes[i].targetY = positions[i * 2 + 1];
      } else {
        nodes[i].targetX = padding + math.Random().nextDouble() * (w - padding * 2);
        nodes[i].targetY = padding + math.Random().nextDouble() * (h - padding * 2);
      }
    }
  }

  void _organizeCircular() {
    if (nodes.isEmpty) return;
    _isSettled = false;
    if (!_controller.isAnimating) _controller.repeat();
    
    final centerX = MediaQuery.of(context).size.width / 2 / _scale;
    final centerY = MediaQuery.of(context).size.height / 2 / _scale;
    
    final minGap = 120.0;
    final circumference = nodes.length * minGap;
    final radius = circumference / (2 * math.pi);
    
    for (int i = 0; i < nodes.length; i++) {
      final angle = (i / nodes.length) * 2 * math.pi;
      nodes[i].targetX = centerX + math.cos(angle) * radius;
      nodes[i].targetY = centerY + math.sin(angle) * radius;
    }
  }

  void _organizeGrid() {
    if (nodes.isEmpty) return;
    _isSettled = false;
    if (!_controller.isAnimating) _controller.repeat();
    
    final spacing = 120.0;
    final cols = (math.sqrt(nodes.length)).ceil();
    final rows = (nodes.length / cols).ceil();
    final startX = (MediaQuery.of(context).size.width - cols * spacing) / 2 / _scale;
    final startY = (MediaQuery.of(context).size.height - rows * spacing) / 2 / _scale;
    
    for (int i = 0; i < nodes.length; i++) {
      final row = i ~/ cols;
      final col = i % cols;
      nodes[i].targetX = startX + col * spacing;
      nodes[i].targetY = startY + row * spacing;
    }
  }

  void _organizeStar() {
    if (nodes.isEmpty) return;
    _isSettled = false;
    if (!_controller.isAnimating) _controller.repeat();
    
    final centerX = MediaQuery.of(context).size.width / 2 / _scale;
    final centerY = MediaQuery.of(context).size.height / 2 / _scale;
    
    final links = <String, int>{};
    for (final edge in edges) {
      if (edge.target >= 0 && edge.target < nodes.length) {
        links[nodes[edge.target].id] = (links[nodes[edge.target].id] ?? 0) + 1;
      }
    }
    
    int maxLinks = 0;
    int centerNode = 0;
    for (int i = 0; i < nodes.length; i++) {
      final linkCount = links[nodes[i].id] ?? 0;
      if (linkCount > maxLinks) {
        maxLinks = linkCount;
        centerNode = i;
      }
    }
    
    nodes[centerNode].targetX = centerX;
    nodes[centerNode].targetY = centerY;
    
    final others = <int>[];
    for (int i = 0; i < nodes.length; i++) {
      if (i != centerNode) others.add(i);
    }
    
    final minGap = 120.0;
    final minRadius = (others.length * minGap) / (2 * math.pi);
    final radius = minRadius.clamp(180.0, 500.0);
    
    for (int i = 0; i < others.length; i++) {
      final angle = (i / others.length) * 2 * math.pi;
      nodes[others[i]].targetX = centerX + math.cos(angle) * radius;
      nodes[others[i]].targetY = centerY + math.sin(angle) * radius;
    }
  }

  void _refreshGraph() async {
    final newProject = await _loadProjectFromDisk(widget.project.name);
    final savedPositions = await KnotService.loadNodePositions(widget.project.name);
    final savedStatic = await KnotService.loadStaticNodes(widget.project.name);
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final padding = 180.0;
    
    nodes = newProject.notes.asMap().entries.map((e) {
      final savedPos = savedPositions?[e.value.name];
      final isNodeStatic = savedStatic?[e.value.name] ?? false;
      return _NodeData(
        id: e.value.name,
        x: savedPos?['x'] ?? (padding + math.Random().nextDouble() * (w - padding * 2)),
        y: savedPos?['y'] ?? (padding + math.Random().nextDouble() * (h - padding * 2)),
        vx: 0,
        vy: 0,
        targetX: savedPos?['x'],
        targetY: savedPos?['y'],
        isVoice: e.value.isVoiceNote,
        isStatic: isNodeStatic,
      );
    }).toList();

    final externalProjects = <String>{};
    edges = newProject.links.map((link) {
      final sourceIndex = nodes.indexWhere((n) => n.id == link.source);
      if (link.isInterProject) {
        externalProjects.add(link.interProject!);
        if (sourceIndex >= 0) return _EdgeData(source: sourceIndex, target: -1, isInterProject: true, interProject: link.interProject);
      } else {
        final targetIndex = nodes.indexWhere((n) => n.id == link.target);
        if (sourceIndex >= 0 && targetIndex >= 0) return _EdgeData(source: sourceIndex, target: targetIndex);
      }
      return null;
    }).whereType<_EdgeData>().toList();

    int extIndex = nodes.length;
    for (final proj in externalProjects) {
      nodes.add(_NodeData(id: proj, x: w / 2 + (extIndex - nodes.length) * 30, y: h / 2 + 200, vx: 0, vy: 0, isExternal: true));
      for (int i = 0; i < edges.length; i++) {
        if (edges[i].isInterProject && edges[i].interProject == proj) {
          edges[i] = _EdgeData(source: edges[i].source, target: extIndex, isInterProject: true, interProject: proj);
        }
      }
      extIndex++;
    }
    setState(() {});
  }

  Future<Project> _loadProjectFromDisk(String projectName) async {
    final knotDir = await KnotService.getKnotDir();
    final projectPath = '$knotDir/$projectName';
    final dir = Directory(projectPath);

    final notes = <Note>[];
    final links = <Link>[];
    final noteFiles = <String, String>{};
    final voiceFiles = <String>{};
    final voiceNoteFiles = <String, String>{};

    await for (final entity in dir.list()) {
      if (entity is File) {
        if (entity.path.endsWith('.md')) {
          final mdPath = entity.path;
          final name = mdPath.split('/').last.replaceAll('.md', '');
          final voicePath = mdPath.replaceAll('.md', '.m4a');
          if (await File(voicePath).exists()) {
            continue;
          }
          final content = await entity.readAsString();
          noteFiles[name] = content;
          notes.add(Note.fromMarkdown(name, content, entity.path));
        } else if (entity.path.endsWith('.m4a')) {
          final name = entity.path.split('/').last.replaceAll('.m4a', '');
          voiceFiles.add(name);
          final mdPath = entity.path.replaceAll('.m4a', '.md');
          String voiceContent = '';
          if (await File(mdPath).exists()) {
            voiceContent = await File(mdPath).readAsString();
            voiceNoteFiles[name] = voiceContent;
          }
          final preview = voiceContent.isNotEmpty 
              ? (voiceContent.length > 100 ? '${voiceContent.substring(0, 100)}...' : voiceContent)
              : 'Voice note';
          notes.add(Note(name: name, content: voiceContent, preview: preview, tags: [], type: 'voice', filePath: entity.path));
        }
      }
    }

    for (final entry in noteFiles.entries) {
      final source = entry.key;
      final content = entry.value;
      final wikiLinks = RegExp(r'\[\[([^\]]+)\]\]').allMatches(content);
      for (final match in wikiLinks) {
        final target = match.group(1)!;
        if (noteFiles.containsKey(target) || voiceFiles.contains(target)) links.add(Link(source: source, target: target));
      }
      final interLinks = RegExp(r'\[\[([^\]]+):([^\]]+)\]\]').allMatches(content);
      for (final match in interLinks) {
        links.add(Link(source: source, target: match.group(2)!, isInterProject: true, interProject: match.group(1)));
      }
    }

    for (final entry in voiceNoteFiles.entries) {
      final source = entry.key;
      final content = entry.value;
      final wikiLinks = RegExp(r'\[\[([^\]]+)\]\]').allMatches(content);
      for (final match in wikiLinks) {
        final target = match.group(1)!;
        if (noteFiles.containsKey(target) || voiceFiles.contains(target)) links.add(Link(source: source, target: target));
      }
      final interLinks = RegExp(r'\[\[([^\]]+):([^\]]+)\]\]').allMatches(content);
      for (final match in interLinks) {
        links.add(Link(source: source, target: match.group(2)!, isInterProject: true, interProject: match.group(1)));
      }
    }

    return Project(name: widget.project.name, path: projectPath, notes: notes, links: links);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00d4ff)),
          onPressed: () async {
            await _saveNodePositions();
            if (mounted) Navigator.pop(context);
          },
        ),
        title: Text(widget.project.name, style: const TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Color(0xFF00d4ff)), onPressed: _showSearch),
          IconButton(
            icon: Icon(Icons.map, color: _showMinimap ? const Color(0xFFff006e) : const Color(0xFF00d4ff)),
            onPressed: () => setState(() => _showMinimap = !_showMinimap),
          ),
          IconButton(
            icon: Icon(_globalStaticMode ? Icons.pause_circle : Icons.play_circle, color: _globalStaticMode ? const Color(0xFF00ff88) : const Color(0xFF00d4ff)),
            onPressed: () {
              setState(() => _globalStaticMode = !_globalStaticMode);
              SettingsService.update((s) => s.globalStaticMode = _globalStaticMode);
            },
            tooltip: _globalStaticMode ? 'Enable Physics' : 'Freeze All',
          ),
          if (_selectedStaticNode != null)
            IconButton(
              icon: const Icon(Icons.push_pin, color: Color(0xFF00ff88)),
              onPressed: _unpinNode,
            ),
        ],
      ),
      body: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onTapUp: _onTapUp,
        onLongPressStart: (details) => _showNotePreview(details.localPosition),
        child: Container(
          color: const Color(0xFF0a0a0f),
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _GraphPainter(
                    nodes: nodes,
                    edges: edges,
                    selectedNode: _selectedNode,
                    scale: _scale,
                    offset: _offset,
                    searchQuery: _searchQuery,
                    highlightedNode: _highlightedNode,
                    highlightPulse: _highlightPulse,
                    time: _time,
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2d2d44)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${nodes.length} nodes', style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 12)),
                      Text('${edges.length} links', style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                    ],
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _isDraggingToTrash ? 0 : -100,
                left: 0,
                right: 0,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    border: Border(top: BorderSide(color: const Color(0xFFff006e).withOpacity(0.5))),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, color: Colors.white, size: 32),
                        SizedBox(height: 4),
                        Text('Drop to delete', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _createNewNote,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1a1a2e),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF00d4ff)),
                        ),
                        child: const Icon(Icons.add, color: Color(0xFF00d4ff), size: 24),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _recenter,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1a1a2e),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF7b2cbf)),
                        ),
                        child: const Icon(Icons.center_focus_strong, color: Color(0xFF7b2cbf), size: 24),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _showOrganizeMenu(),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00d4ff),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, color: Color(0xFF0a0a0f), size: 20),
                            SizedBox(width: 8),
                            Text('Organize', style: TextStyle(color: Color(0xFF0a0a0f), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_showMinimap) _buildMinimap(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimap() {
    final screenSize = MediaQuery.of(context).size;
    const miniWidth = 140.0;
    const miniHeight = 100.0;
    
    double minX = nodes.isEmpty ? 0 : nodes[0].x;
    double maxX = minX;
    double minY = minX;
    double maxY = minX;
    for (final n in nodes) {
      if (n.x < minX) minX = n.x;
      if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.y > maxY) maxY = n.y;
    }
    final graphW = (maxX - minX + 300).clamp(400.0, 10000.0);
    final graphH = (maxY - minY + 300).clamp(400.0, 10000.0);
    final miniScale = (miniWidth / graphW) < (miniHeight / graphH) 
        ? miniWidth / graphW 
        : miniHeight / graphH;
    final offsetX = (miniWidth - graphW * miniScale) / 2 - minX * miniScale;
    final offsetY = (miniHeight - graphH * miniScale) / 2 - minY * miniScale;
    
    final worldLeft = -_offset.dx / _scale;
    final worldTop = -_offset.dy / _scale;
    final worldRight = worldLeft + screenSize.width / _scale;
    final worldBottom = worldTop + screenSize.height / _scale;
    
    final viewX = (worldLeft * miniScale + offsetX).clamp(0.0, miniWidth);
    final viewY = (worldTop * miniScale + offsetY).clamp(0.0, miniHeight);
    final viewW = ((worldRight - worldLeft) * miniScale).clamp(20.0, miniWidth - viewX);
    final viewH = ((worldBottom - worldTop) * miniScale).clamp(15.0, miniHeight - viewY);
    
    return Positioned(
      top: 20,
      right: 80,
      child: GestureDetector(
        onTapUp: (details) {
          final tapX = details.localPosition.dx;
          final tapY = details.localPosition.dy;
          
          final worldX = (tapX - offsetX) / miniScale;
          final worldY = (tapY - offsetY) / miniScale;
          
          setState(() {
            _offset = Offset(
              -worldX * _scale + screenSize.width / 2,
              -worldY * _scale + screenSize.height / 2,
            );
          });
        },
        child: Container(
          width: miniWidth,
          height: miniHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a2e).withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00d4ff).withOpacity(0.5)),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: CustomPaint(
                  size: const Size(miniWidth, miniHeight),
                  painter: _MinimapPainter(
                    nodes: nodes,
                    edges: edges,
                    miniScale: miniScale,
                    offsetX: offsetX,
                    offsetY: offsetY,
                  ),
                ),
              ),
              Positioned(
                left: viewX,
                top: viewY,
                child: Container(
                  width: viewW,
                  height: viewH,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00d4ff).withOpacity(0.15),
                    border: Border.all(color: const Color(0xFF00d4ff), width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final List<_NodeData> nodes;
  final List<_EdgeData> edges;
  final double miniScale;
  final double offsetX;
  final double offsetY;

  _MinimapPainter({
    required this.nodes,
    required this.edges,
    required this.miniScale,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    
    final edgePaint = Paint()
      ..color = const Color(0xFF00d4ff).withOpacity(0.4)
      ..strokeWidth = 1;
    for (final edge in edges) {
      if (edge.target < 0 || edge.target >= nodes.length) continue;
      canvas.drawLine(
        Offset(nodes[edge.source].x * miniScale + offsetX, nodes[edge.source].y * miniScale + offsetY),
        Offset(nodes[edge.target].x * miniScale + offsetX, nodes[edge.target].y * miniScale + offsetY),
        edgePaint,
      );
    }
    
    final nodePaint = Paint()..color = const Color(0xFF00d4ff);
    for (final node in nodes) {
      canvas.drawCircle(
        Offset(node.x * miniScale + offsetX, node.y * miniScale + offsetY),
        2.5,
        nodePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return nodes != oldDelegate.nodes ||
        edges != oldDelegate.edges ||
        miniScale != oldDelegate.miniScale ||
        offsetX != oldDelegate.offsetX ||
        offsetY != oldDelegate.offsetY;
  }
}

class _NodeData {
  String id;
  double x;
  double y;
  double vx;
  double vy;
  double? targetX;
  double? targetY;
  bool isExternal;
  bool isVoice;
  bool isStatic;
  _NodeData({
    required this.id,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.targetX,
    this.targetY,
    this.isExternal = false,
    this.isVoice = false,
    this.isStatic = false,
  });
}

class _EdgeData {
  int source;
  int target;
  bool isInterProject;
  String? interProject;
  _EdgeData({
    required this.source,
    required this.target,
    this.isInterProject = false,
    this.interProject,
  });
}

class _GraphPainter extends CustomPainter {
  final List<_NodeData> nodes;
  final List<_EdgeData> edges;
  final String? selectedNode;
  final double scale;
  final Offset offset;
  final String? highlightedNode;
  final double highlightPulse;
  final double time;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    required this.scale,
    required this.offset,
    this.searchQuery = '',
    this.highlightedNode,
    this.highlightPulse = 0.0,
    required this.time,
  });

  final String searchQuery;

  @override
  void paint(Canvas canvas, Size size) {
    final s = SettingsService.settings;
    final accentColors = [const Color(0xFF00d4ff), const Color(0xFFff006e), const Color(0xFF7b2cbf), const Color(0xFF00ff88)];
    final accent = accentColors[s.accentColorIndex];

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    if (s.showEdges) {
      final edgeGlowIntensity = s.edgeGlow / 100;
      for (final edge in edges) {
        if (edge.target < 0 || edge.target >= nodes.length) continue;
        final start = nodes[edge.source];
        final end = nodes[edge.target];
        final midX = (start.x + end.x) / 2;
        final midY = (start.y + end.y) / 2;
        final path = Path()
          ..moveTo(start.x, start.y)
          ..quadraticBezierTo(midX - (end.y - start.y) * 0.02, midY + (end.x - start.x) * 0.02, end.x, end.y);
        final edgeColor = edge.isInterProject ? const Color(0xFFff4444) : accent;
        
        if (edgeGlowIntensity > 0) {
          canvas.drawPath(
            path,
            Paint()
              ..color = edgeColor.withOpacity(0.4 * edgeGlowIntensity)
              ..strokeWidth = (edge.isInterProject ? 3 : s.edgeThickness) + 12 * edgeGlowIntensity
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * edgeGlowIntensity),
          );
        }
        
        canvas.drawPath(
          path,
          Paint()
            ..color = edgeColor.withOpacity(0.6)
            ..strokeWidth = edge.isInterProject ? 3 : s.edgeThickness
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    for (final node in nodes) {
      final isSelected = selectedNode == node.id;
      final isMatch = searchQuery.isNotEmpty && node.id.toLowerCase().contains(searchQuery.toLowerCase());
      final isHighlighted = highlightedNode == node.id;
      final color = node.isExternal
          ? const Color(0xFF9d4edd)
          : (node.isVoice 
              ? const Color(0xFF00ff88) 
              : (isHighlighted 
                  ? const Color(0xFFff006e) 
                  : (isSelected ? const Color(0xFFff006e) : (isMatch ? const Color(0xFF00ff88) : accent))));

      final glowIntensity = s.nodeGlowIntensity / 100;
      final baseNodeSize = 30.0 * s.nodeSize;
      final isLowEnd = s.lowEndDevice;
      
      if (glowIntensity > 0 && !isLowEnd) {
        canvas.drawCircle(
          Offset(node.x, node.y),
          60 * s.nodeSize,
          Paint()
            ..color = color.withOpacity(0.06 * glowIntensity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
        );
        canvas.drawCircle(
          Offset(node.x, node.y),
          42 * s.nodeSize,
          Paint()
            ..color = color.withOpacity(0.12 * glowIntensity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
        canvas.drawCircle(
          Offset(node.x, node.y),
          30 * s.nodeSize,
          Paint()
            ..color = color.withOpacity(0.2 * glowIntensity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }

      final double nodeSize = isSelected ? 24.0 * s.nodeSize : 18.0 * s.nodeSize;
      if (glowIntensity > 0 && !isLowEnd) {
        final glowPaint = Paint()
          ..color = color.withOpacity(0.5 * glowIntensity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(Offset(node.x, node.y), nodeSize + 4, glowPaint);
      }
      canvas.drawCircle(
        Offset(node.x, node.y),
        nodeSize,
        Paint()..color = const Color(0xFF0a0a0f)..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(node.x, node.y),
        nodeSize,
        Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke,
      );

      if (node.isExternal) {
        canvas.drawCircle(
          Offset(node.x, node.y),
          22 * s.nodeSize,
          Paint()
            ..color = const Color(0xFF9d4edd).withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }

      if (node.isVoice) {
        for (int i = 0; i < 3; i++) {
          final waveRadius = 22 * s.nodeSize + (time * 10 + i * 12) % 18;
          final opacity = (1 - waveRadius / 40).clamp(0.0, 0.4);
          canvas.drawCircle(
            Offset(node.x, node.y),
            waveRadius,
            Paint()
              ..color = const Color(0xFF00ff88).withOpacity(opacity)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }

      if (highlightedNode == node.id && highlightPulse > 0) {
        final pulseRadius = 30 * s.nodeSize + highlightPulse * 20;
        final opacity = (1 - highlightPulse) * 0.6;
        canvas.drawCircle(
          Offset(node.x, node.y),
          pulseRadius,
          Paint()
            ..color = const Color(0xFFff006e).withOpacity(opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }

      final labelColor = node.isExternal ? const Color(0xFF9d4edd) : accent;
      final labelFontSize = 10.0 * s.labelSize;
      
      if (node.isStatic) {
        canvas.drawCircle(
          Offset(node.x, node.y),
          28 * s.nodeSize,
          Paint()
            ..color = const Color(0xFF00ff88).withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        final pinPath = Path()
          ..moveTo(node.x + 20 * s.nodeSize, node.y - 20 * s.nodeSize)
          ..lineTo(node.x + 28 * s.nodeSize, node.y - 28 * s.nodeSize);
        canvas.drawPath(
          pinPath,
          Paint()
            ..color = const Color(0xFF00ff88)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          Offset(node.x + 28 * s.nodeSize, node.y - 28 * s.nodeSize),
          4,
          Paint()..color = const Color(0xFF00ff88),
        );
      }
      
      final tp = TextPainter(
        text: TextSpan(
          text: node.id.length > 10 ? '${node.id.substring(0, 8)}...' : node.id,
          style: TextStyle(color: labelColor, fontSize: labelFontSize, fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(node.x - tp.width / 2, node.y + 16 * s.nodeSize));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return nodes != oldDelegate.nodes ||
        edges != oldDelegate.edges ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset ||
        selectedNode != oldDelegate.selectedNode ||
        searchQuery != oldDelegate.searchQuery ||
        highlightedNode != oldDelegate.highlightedNode ||
        highlightPulse != oldDelegate.highlightPulse ||
        time != oldDelegate.time;
  }
}

class _NotePreviewDialog extends StatefulWidget {
  final Note note;
  final bool isVoice;
  final bool isStatic;
  final List<String> backlinks;
  final List<String> forwardLinks;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onUnpin;

  const _NotePreviewDialog({
    required this.note,
    required this.isVoice,
    required this.isStatic,
    required this.backlinks,
    required this.forwardLinks,
    required this.onDelete,
    required this.onPin,
    required this.onUnpin,
  });

  @override
  State<_NotePreviewDialog> createState() => _NotePreviewDialogState();
}

class _NotePreviewDialogState extends State<_NotePreviewDialog> {
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.isVoice) _initAudio();
  }

  Future<void> _initAudio() async {
    if (widget.note.filePath == null) return;
    _audioPlayer = AudioPlayer();
    await _audioPlayer!.setSourceDeviceFile(widget.note.filePath!);
    final dur = await _audioPlayer!.getDuration();
    if (mounted) setState(() => _duration = dur ?? Duration.zero);
    _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer!.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
  }

  Future<void> _togglePlayPause() async {
    if (_audioPlayer == null) return;
    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.resume();
    }
  }

  Future<void> _seek(double val) async {
    if (_audioPlayer == null) return;
    await _audioPlayer!.seek(Duration(milliseconds: val.toInt()));
  }

  Widget _buildMarkdownContent(String content) {
    if (content.isEmpty) return const SizedBox.shrink();
    
    final spans = <TextSpan>[];
    final lines = content.split('\n');
    
    for (var line in lines) {
      if (line.startsWith('#### ')) {
        spans.addAll(_parseInlineStylesWithColor(line.substring(6), const TextStyle(color: Color(0xFF00d4ff), fontSize: 12, fontWeight: FontWeight.bold)));
      } else if (line.startsWith('### ')) {
        spans.addAll(_parseInlineStylesWithColor(line.substring(4), const TextStyle(color: Color(0xFF00d4ff), fontSize: 14, fontWeight: FontWeight.bold)));
      } else if (line.startsWith('## ')) {
        spans.addAll(_parseInlineStylesWithColor(line.substring(3), const TextStyle(color: Color(0xFF00d4ff), fontSize: 16, fontWeight: FontWeight.bold)));
      } else if (line.startsWith('# ')) {
        spans.addAll(_parseInlineStylesWithColor(line.substring(2), const TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)));
      } else if (line.startsWith('- ')) {
        spans.add(TextSpan(text: '  • ', style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 14)));
        spans.addAll(_parseInlineStyles(line.substring(2)));
      } else if (line.trim().isEmpty) {
        spans.add(const TextSpan(text: '\n'));
      } else {
        spans.addAll(_parseInlineStyles(line));
      }
      spans.add(const TextSpan(text: '\n'));
    }
    
    return RichText(text: TextSpan(children: spans));
  }

  List<TextSpan> _parseInlineStylesWithColor(String text, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    var currentIndex = 0;
    final pattern = RegExp(r'(\[\[([^\]]+)\]\])|(\*\*\*(.+?)\*\*\*)|(\*\*(.+?)\*\*)|(\*(.+?)\*)');
    
    for (final match in pattern.allMatches(text)) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, match.start), style: baseStyle));
      }
      
      if (match.group(1) != null) {
        spans.add(TextSpan(text: '@${match.group(2)}', style: const TextStyle(color: Color(0xFF7b2cbf), fontWeight: FontWeight.w500)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(4), style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)));
      } else if (match.group(5) != null) {
        spans.add(TextSpan(text: match.group(6), style: baseStyle.copyWith(fontWeight: FontWeight.bold)));
      } else if (match.group(7) != null) {
        spans.add(TextSpan(text: match.group(8), style: baseStyle.copyWith(fontStyle: FontStyle.italic)));
      }
      currentIndex = match.end;
    }
    
    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex), style: baseStyle));
    }
    
    return spans;
  }

  List<TextSpan> _parseInlineStyles(String text) {
    final spans = <TextSpan>[];
    var currentIndex = 0;
    final pattern = RegExp(r'(\[\[([^\]]+)\]\])|(\*\*\*(.+?)\*\*\*)|(\*\*(.+?)\*\*)|(\*(.+?)\*)');
    
    for (final match in pattern.allMatches(text)) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, match.start), style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 14)));
      }
      
      if (match.group(1) != null) {
        spans.add(TextSpan(text: '@${match.group(2)}', style: const TextStyle(color: Color(0xFF7b2cbf), fontWeight: FontWeight.w500)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(4), style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 14, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)));
      } else if (match.group(5) != null) {
        spans.add(TextSpan(text: match.group(6), style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 14, fontWeight: FontWeight.bold)));
      } else if (match.group(7) != null) {
        spans.add(TextSpan(text: match.group(8), style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 14, fontStyle: FontStyle.italic)));
      }
      currentIndex = match.end;
    }
    
    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex), style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 14)));
    }
    
    return spans;
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Expanded(child: Text(widget.note.name, style: const TextStyle(color: Color(0xFF00d4ff)))),
          if (widget.isVoice) const Icon(Icons.mic, color: Color(0xFF00ff88), size: 20),
        ],
      ),
      content: SizedBox(
        width: 320,
        height: 280,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isVoice && widget.note.filePath != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0a0a0f),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: const Color(0xFF00ff88), size: 32),
                            onPressed: _togglePlayPause,
                          ),
                        ],
                      ),
                      Slider(
                        value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                        max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                        activeColor: const Color(0xFF00ff88),
                        inactiveColor: const Color(0xFF2d2d44),
                        onChanged: _seek,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.note.content.isNotEmpty)
                _buildMarkdownContent(widget.note.content.length > 300 ? '${widget.note.content.substring(0, 300)}...' : widget.note.content)
              else if (!widget.isVoice)
                Text('(empty note)', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              if (widget.forwardLinks.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF2d2d44)),
                const Text('Links to', style: TextStyle(color: Color(0xFF7b2cbf), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: widget.forwardLinks.map((l) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF7b2cbf).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text('@$l', style: const TextStyle(color: Color(0xFF7b2cbf), fontSize: 10)),
                  )).toList(),
                ),
              ],
              if (widget.backlinks.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF2d2d44)),
                const Text('Linked from', style: TextStyle(color: Color(0xFF7b2cbf), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: widget.backlinks.map((b) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF7b2cbf).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text('@$b', style: const TextStyle(color: Color(0xFF7b2cbf), fontSize: 10)),
                  )).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.isStatic)
          TextButton(onPressed: () { widget.onUnpin(); }, child: const Text('Unpin', style: TextStyle(color: Color(0xFF00ff88)))),
        if (!widget.isStatic)
          TextButton(onPressed: () { widget.onPin(); }, child: const Text('Pin', style: TextStyle(color: Color(0xFF00ff88)))),
        TextButton(onPressed: () { widget.onDelete(); Navigator.pop(context); }, child: const Text('Delete', style: TextStyle(color: Color(0xFFff006e)))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: TextStyle(color: Colors.grey[500]))),
        TextButton(onPressed: () async { Navigator.pop(context); }, child: const Text('Open', style: TextStyle(color: Color(0xFF00d4ff)))),
      ],
    );
  }
}