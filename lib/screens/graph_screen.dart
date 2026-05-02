import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io';
import 'dart:collection';
import '../models/note.dart';
import '../services/knot_service.dart';
import 'note_detail_screen.dart';

class GraphScreen extends StatefulWidget {
  final Project project;

  const GraphScreen({super.key, required this.project});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> with TickerProviderStateMixin {
  late List<_NodeData> nodes;
  late List<_EdgeData> edges;
  late AnimationController _controller;
  int? _draggedNode;
  String? _selectedNode;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _isDraggingToTrash = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _controller.addListener(_updatePhysics);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initGraph();
  }

  void _initGraph() {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    nodes = widget.project.notes.asMap().entries.map((e) {
      final angle = e.key * 2 * 3.14159 / widget.project.notes.length;
      final radius = 120.0 + e.key * 30;
      return _NodeData(
        id: e.value.name,
        x: w / 2 + math.cos(angle) * radius,
        y: h / 2 + math.sin(angle) * radius,
        vx: 0,
        vy: 0,
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
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount == 1) {
      final scaleOffset = Offset(_offset.dx / _scale, _offset.dy / _scale);
      final pos = (details.localFocalPoint - scaleOffset) / _scale;
      for (var i = 0; i < nodes.length; i++) {
        final dx = nodes[i].x - pos.dx;
        final dy = nodes[i].y - pos.dy;
        if (math.sqrt(dx * dx + dy * dy) < 50) {
          _draggedNode = i;
          break;
        }
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
    } else {
      setState(() {
        _scale = (_scale * details.scale).clamp(0.3, 3.0);
        _offset = details.focalPoint - details.focalPoint;
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) async {
    if (_draggedNode != null && _isDraggingToTrash) {
      final node = nodes[_draggedNode!];
      if (!node.isExternal) {
        final file = File('${widget.project.path}/${node.id}.md');
        if (await file.exists()) {
          await file.delete();
          _refreshGraph();
        }
      }
    }
    _draggedNode = null;
    _isDraggingToTrash = false;
  }

  double _time = 0;

  void _updatePhysics() {
    if (nodes.isEmpty) return;
    _time += 0.02;

    final centerX = MediaQuery.of(context).size.width / 2 / _scale;
    final centerY = MediaQuery.of(context).size.height / 2 / _scale;

    for (var i = 0; i < nodes.length; i++) {
      final floatX = math.sin(_time * 0.3 + i * 0.7) * 15;
      final floatY = math.cos(_time * 0.25 + i * 0.5) * 12;

      final dxCenter = (centerX + floatX) - nodes[i].x;
      final dyCenter = (centerY + floatY) - nodes[i].y;
      nodes[i].vx += dxCenter * 0.0008;
      nodes[i].vy += dyCenter * 0.0008;
    }

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final dx = nodes[j].x - nodes[i].x;
        final dy = nodes[j].y - nodes[i].y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist > 0 && dist < 300) {
          final repulsion = 4000 / (dist * dist + 100);
          final nx = dx / dist;
          final ny = dy / dist;
          nodes[i].vx -= nx * repulsion * 0.15;
          nodes[i].vy -= ny * repulsion * 0.15;
          nodes[j].vx += nx * repulsion * 0.15;
          nodes[j].vy += ny * repulsion * 0.15;
        }
      }
    }

    for (final edge in edges) {
      if (edge.target < 0 || edge.target >= nodes.length) continue;
      final dx = nodes[edge.target].x - nodes[edge.source].x;
      final dy = nodes[edge.target].y - nodes[edge.source].y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist > 0) {
        final force = (dist - 350) * 0.0004;
        final fx = dx / dist * force;
        final fy = dy / dist * force;
        nodes[edge.source].vx += fx * 0.5;
        nodes[edge.source].vy += fy * 0.5;
        nodes[edge.target].vx -= fx * 0.5;
        nodes[edge.target].vy -= fy * 0.5;
      }
    }

    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].targetX != null) {
        final dx = nodes[i].targetX! - nodes[i].x;
        final dy = nodes[i].targetY! - nodes[i].y;
        nodes[i].vx += dx * 0.02;
        nodes[i].vy += dy * 0.02;
      }

      nodes[i].vx *= 0.98;
      nodes[i].vy *= 0.98;
      nodes[i].x += nodes[i].vx;
      nodes[i].y += nodes[i].vy;
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
          final note = widget.project.notes.firstWhere((n) => n.name == nodes[i].id, orElse: () => Note(name: nodes[i].id, content: '', preview: '', tags: []));
          await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note, filePath: note.filePath)));
          if (mounted) { _refreshGraph(); }
        }
        break;
      }
    }
  }

  Future<void> _createNewNote() async {
    final noteName = 'note_${DateTime.now().millisecondsSinceEpoch}';
    final note = Note(name: noteName, content: '# New Note\n\n', preview: '', tags: []);
    final filePath = '${widget.project.path}/$noteName.md';
    await File(filePath).writeAsString(note.content);
    if (mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note, filePath: filePath)));
      _refreshGraph();
    }
  }

  void _organizeTree() {
    if (nodes.isEmpty) return;

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
    void dfs(int node, double x, double y, double spread) {
      if (visited.contains(node)) return;
      visited.add(node);
      nodes[node].targetX = x;
      nodes[node].targetY = y;
      final children = adjacency[node] ?? [];
      if (children.isNotEmpty) {
        final childSpread = spread / children.length.clamp(1, children.length);
        for (int i = 0; i < children.length; i++) {
          dfs(children[i], x - spread / 2 + childSpread * i + childSpread / 2, y + 150, childSpread * 0.8);
        }
      }
    }

    for (int i = 0; i < roots.length; i++) {
      dfs(roots[i], centerX + (i - roots.length / 2) * 250, centerY - 150, 400.0 / roots.length);
    }

    for (int i = 0; i < nodes.length; i++) {
      if (!visited.contains(i)) {
        nodes[i].targetX = centerX + (math.Random().nextDouble() - 0.5) * 200;
        nodes[i].targetY = centerY + (math.Random().nextDouble() - 0.5) * 200;
      }
    }
  }

  void _refreshGraph() async {
    final newProject = await _loadProjectFromDisk(widget.project.name);
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    nodes = newProject.notes.asMap().entries.map((e) {
      final angle = e.key * 2 * 3.14159 / newProject.notes.length;
      final radius = 80.0 + e.key * 15;
      return _NodeData(
        id: e.value.name,
        x: w / 2 + math.cos(angle) * radius,
        y: h / 2 + math.sin(angle) * radius,
        vx: 0,
        vy: 0,
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

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        final content = await entity.readAsString();
        final name = entity.path.split('/').last.replaceAll('.md', '');
        noteFiles[name] = content;
        notes.add(Note.fromMarkdown(name, content, entity.path));
      }
    }

    for (final entry in noteFiles.entries) {
      final source = entry.key;
      final content = entry.value;
      final wikiLinks = RegExp(r'\[\[(\w+)\]\]').allMatches(content);
      for (final match in wikiLinks) {
        final target = match.group(1)!;
        if (noteFiles.containsKey(target)) links.add(Link(source: source, target: target));
      }
      final interLinks = RegExp(r'\[\[(\w+):(\w+)\]\]').allMatches(content);
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.project.name, style: const TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold)),
      ),
      body: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onTapUp: _onTapUp,
        child: Container(
          color: const Color(0xFF0a0a0f),
          child: Stack(
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: _GraphPainter(
                  nodes: nodes,
                  edges: edges,
                  selectedNode: _selectedNode,
                  scale: _scale,
                  offset: _offset,
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
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFff006e).withOpacity(0.3),
                        const Color(0xFFff006e).withOpacity(0.8),
                      ],
                    ),
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
                      onTap: _organizeTree,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFff006e), Color(0xFF7b2cbf)]),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('wow', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  _NodeData({
    required this.id,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.targetX,
    this.targetY,
    this.isExternal = false,
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

  _GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    required this.scale,
    required this.offset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    for (final edge in edges) {
      if (edge.target < 0 || edge.target >= nodes.length) continue;
      final start = nodes[edge.source];
      final end = nodes[edge.target];
      final midX = (start.x + end.x) / 2;
      final midY = (start.y + end.y) / 2;
      final dx = end.x - start.x;
      final dy = end.y - start.y;
      final path = Path()
        ..moveTo(start.x, start.y)
        ..quadraticBezierTo(midX - dy * 0.1, midY + dx * 0.1, end.x, end.y);
      final edgeColor = edge.isInterProject ? const Color(0xFFff006e) : const Color(0xFF7b2cbf);
      canvas.drawPath(
        path,
        Paint()
          ..color = edgeColor.withOpacity(0.6)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final node in nodes) {
      final isSelected = selectedNode == node.id;
      final color = node.isExternal
          ? const Color(0xFF9d4edd)
          : (isSelected ? const Color(0xFFff006e) : const Color(0xFF00d4ff));

      canvas.drawCircle(
        Offset(node.x, node.y),
        60,
        Paint()
          ..color = color.withOpacity(0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
      canvas.drawCircle(
        Offset(node.x, node.y),
        42,
        Paint()
          ..color = color.withOpacity(0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      canvas.drawCircle(
        Offset(node.x, node.y),
        30,
        Paint()
          ..color = color.withOpacity(0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );

      final double nodeSize = isSelected ? 34.0 : 26.0;
      canvas.drawCircle(
        Offset(node.x, node.y),
        nodeSize,
        Paint()..color = const Color(0xFF1a1a2e)..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(node.x, node.y),
        nodeSize,
        Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke,
      );

      if (node.isExternal) {
        canvas.drawCircle(
          Offset(node.x, node.y),
          22,
          Paint()
            ..color = const Color(0xFF9d4edd).withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }

      final labelColor = node.isExternal ? const Color(0xFF9d4edd) : const Color(0xFF00d4ff);
      final tp = TextPainter(
        text: TextSpan(
          text: node.id.length > 10 ? '${node.id.substring(0, 8)}...' : node.id,
          style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(node.x - tp.width / 2, node.y + 24));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}