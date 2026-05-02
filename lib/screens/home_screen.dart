import 'package:flutter/material.dart';
import 'dart:io';
import '../services/knot_service.dart';
import '../models/note.dart';
import 'graph_screen.dart';

class _ProjectData {
  final String name;
  final int noteCount;
  _ProjectData({required this.name, required this.noteCount});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<_ProjectData> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    final names = await KnotService.getProjects();
    final data = <_ProjectData>[];
    for (final name in names) {
      final count = await KnotService.getNoteCount(name);
      data.add(_ProjectData(name: name, noteCount: count));
    }
    setState(() { _projects = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0a0a0f), Color(0xFF12121a)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Knot', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 32, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('your knowledge graph', style: TextStyle(color: Color(0xFF7b2cbf), fontSize: 14)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1a2e),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF2d2d44)),
                      ),
                      child: const Icon(Icons.blur_circular, color: Color(0xFF00d4ff), size: 28),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GestureDetector(
                  onTap: _createProject,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF00d4ff), Color(0xFF7b2cbf)]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Colors.white),
                        SizedBox(width: 8),
                        Text('New Project', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('Projects', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00d4ff)))
                    : _projects.isEmpty
                        ? Center(child: Text('No projects yet', style: TextStyle(color: Colors.grey[600])))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _projects.length,
                            itemBuilder: (context, index) => _ProjectCard(
                              name: _projects[index].name,
                              noteCount: _projects[index].noteCount,
                              onTap: () async {
                                final proj = await KnotService.loadProject(_projects[index].name);
                                if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => GraphScreen(project: proj)));
                              },
                              onLongPress: () => _deleteProject(_projects[index].name),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Project', style: TextStyle(color: Color(0xFF00d4ff))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Project name',
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

    if (result != null && result.isNotEmpty) {
      final knotDir = await KnotService.getKnotDir();
      final projectDir = Directory('$knotDir/$result');
      await projectDir.create(recursive: true);
      final indexFile = File('${projectDir.path}/index.md');
      await indexFile.writeAsString('# $result\n\nStart writing...\n');
      _loadProjects();
    }
  }

  Future<void> _deleteProject(String projectName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Project?', style: TextStyle(color: Color(0xFFff006e))),
        content: Text('Are you sure you want to delete "$projectName"?', style: const TextStyle(color: Color(0xFFe0e0e0))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFff006e)))),
        ],
      ),
    );

    if (confirm == true) {
      final knotDir = await KnotService.getKnotDir();
      final projectDir = Directory('$knotDir/$projectName');
      await projectDir.delete(recursive: true);
      _loadProjects();
    }
  }
}

class _ProjectCard extends StatelessWidget {
  final String name;
  final int noteCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ProjectCard({required this.name, required this.noteCount, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a1a2e), Color(0xFF16162a)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2d2d44)),
          boxShadow: [BoxShadow(color: const Color(0xFF00d4ff).withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00d4ff).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.account_tree, color: Color(0xFF00d4ff), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('$noteCount notes', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2d2d44).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_forward_ios, color: Color(0xFF00d4ff), size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}