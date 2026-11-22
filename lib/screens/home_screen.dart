import 'dart:io';
import 'package:flutter/material.dart';
import '../services/knot_service.dart';
import '../models/note.dart';
import '../config/app_config.dart';
import 'graph_screen.dart';
import 'settings_screen.dart';
import 'reminder_screen.dart';
import 'money_screen.dart';
import '../services/money_service.dart';
import '../services/notification_service.dart';

class _ProjectData {
  final String name;
  final int noteCount;
  _ProjectData({required this.name, required this.noteCount});
}

class _SearchResult {
  final Note note;
  final String projectName;
  final double score;
  _SearchResult({required this.note, required this.projectName, required this.score});
}

/// Simple fuzzy matcher: returns a score (higher = better match) or null if no match.
/// Rewards consecutive matches, matches at word boundaries, and shorter spans.
double? _fuzzyScore(String query, String target) {
  if (query.isEmpty) return null;
  final q = query.toLowerCase();
  final t = target.toLowerCase();
  int qi = 0;
  int? prevIdx;
  int score = 0;
  int consecutive = 0;
  int spanStart = -1;
  int spanEnd = -1;

  for (int ti = 0; ti < t.length && qi < q.length; ti++) {
    if (t[ti] == q[qi]) {
      if (prevIdx == null) spanStart = ti;
      if (prevIdx != null && ti == prevIdx + 1) {
        consecutive++;
        score += 10 + consecutive * 5; // bonus for consecutive
      } else {
        consecutive = 1;
        score += 5;
      }
      // Bonus for match at word boundary (start or after space/-/_/)
      if (ti == 0 || t[ti - 1] == ' ' || t[ti - 1] == '-' || t[ti - 1] == '_' || t[ti - 1] == '.') {
        score += 8;
      }
      prevIdx = ti;
      spanEnd = ti;
      qi++;
    }
  }

  if (qi < q.length) return null; // not all query chars found in order

  // Penalty for long span between first and last match
  if (spanStart >= 0 && spanEnd >= 0) {
    final span = spanEnd - spanStart + 1;
    score -= (span - q.length) * 2;
  }

  // Bonus if target starts with query (prefix match)
  if (t.startsWith(q)) score += 50;

  return score.toDouble();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<_ProjectData> _projects = [];
  bool _loading = true;
  String _searchQuery = '';
  bool _searching = false;
  List<_SearchResult> _searchResults = [];
  bool _searchLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _checkPendingMoney();
  }

  Future<void> _checkPendingMoney() async {
    final pending = await MoneyService.getPending();
    if (pending.isNotEmpty && mounted) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) NotificationService.showNextPending(context);
      });
    }
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    final names = await KnotService.getProjects();
    final futures = names.map((name) async {
      final count = await KnotService.getNoteCount(name);
      return _ProjectData(name: name, noteCount: count);
    });
    final data = await Future.wait(futures);
    setState(() { _projects = data; _loading = false; });
  }

  void _onSearchChanged(String q) {
    setState(() {
      _searchQuery = q;
      _searching = q.isNotEmpty;
    });
    _runSearch(q);
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _searchResults = []; _searchLoading = false; });
      return;
    }
    setState(() => _searchLoading = true);
    final results = <_SearchResult>[];
    try {
      final projectNames = await KnotService.getProjects();
      for (final projName in projectNames) {
        // Match project name itself
        final pScore = _fuzzyScore(q, projName);
        if (pScore != null) {
          results.add(_SearchResult(
            note: Note(name: projName, content: '', preview: '', tags: [], type: 'project'),
            projectName: projName,
            score: pScore + 100, // boost project name matches
          ));
        }
        // Match notes inside project
        final proj = await KnotService.loadProject(projName);
        for (final note in proj.notes) {
          final nScore = _fuzzyScore(q, note.name);
          final cScore = _fuzzyScore(q, note.content);
          final scores = [nScore, cScore].whereType<double>();
          if (scores.isNotEmpty) {
            final best = scores.reduce((a, b) => a > b ? a : b);
            results.add(_SearchResult(note: note, projectName: projName, score: best));
          }
        }
      }
      results.sort((a, b) => b.score.compareTo(a.score));
    } catch (_) {}
    if (!mounted) return;
    setState(() { _searchResults = results; _searchLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFF0a0a0f),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Knot', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 32, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a1a2e),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF2d2d44)),
                          ),
                          child: GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReminderScreen())),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.alarm, color: Color(0xFF00ff88), size: 20),
                                SizedBox(width: 4),
                                Text('Reminders', style: TextStyle(color: Color(0xFF00ff88), fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a1a2e),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF2d2d44)),
                          ),
                          child: GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                            child: const Icon(Icons.settings, color: Color(0xFF00d4ff), size: 24),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Inline search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2d2d44)),
                  ),
                  child: TextField(
                    onChanged: _onSearchChanged,
                    autofocus: _searching,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFF00d4ff),
                    decoration: InputDecoration(
                      hintText: _searching ? 'Search notes & projects…' : 'Search projects & notes…',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 15),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF00d4ff), size: 22),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchQuery = '';
                                setState(() { _searchResults = []; _searching = false; });
                              },
                              child: Icon(Icons.clear, color: Colors.grey[600], size: 20),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      filled: true,
                      fillColor: const Color(0xFF1a1a2e),
                    ),
                  ),
                ),
              ),
              if (_searchLoading && _searchQuery.isNotEmpty)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Color(0xFF00d4ff), strokeWidth: 2))),
              const SizedBox(height: 4),

              // New project button + Money shortcut
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: _createProject,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00d4ff),
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
                  )),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoneyScreen())),
                    child: FutureBuilder<List>(
                      future: MoneyService.getPending(),
                      builder: (_, snap) {
                        final count = snap.data?.length ?? 0;
                        return Stack(children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1a1a2e),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF00d4ff)),
                            ),
                            child: const Icon(Icons.account_balance_wallet, color: Color(0xFF00d4ff)),
                          ),
                          if (count > 0) Positioned(top: -2, right: -2, child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Color(0xFFff006e), shape: BoxShape.circle),
                            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          )),
                        ]);
                      },
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),

              // Search results section
              if (_searching && _searchQuery.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Text('Search results', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                    const SizedBox(width: 8),
                    Text('${_searchResults.length}', style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _searchResults.isEmpty
                      ? Center(child: Text('No matches', style: TextStyle(color: Colors.grey[600])))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final r = _searchResults[index];
                            final isProject = r.note.type == 'project';
                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isProject ? const Color(0xFF00d4ff).withOpacity(0.15) : const Color(0xFF7b2cbf).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isProject ? Icons.account_tree : (r.note.isVoiceNote ? Icons.mic : Icons.description),
                                  color: isProject ? const Color(0xFF00d4ff) : const Color(0xFF7b2cbf),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                r.note.name,
                                style: const TextStyle(color: Color(0xFFe0e0e0), fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  isProject ? 'Project • ${_noteCount(r.projectName)} notes' : '${r.projectName} • ${r.note.preview.isNotEmpty ? r.note.preview : 'no content'}',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onTap: () async {
                                setState(() => _searching = false);
                                final proj = await KnotService.loadProject(r.projectName);
                                if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => GraphScreen(project: proj)));
                              },
                            );
                          },
                        ),
                ),
              ] else ...[
                // Projects section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Projects', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF00d4ff)))
                      : _projects.isEmpty
                          ? Center(child: Text('No projects yet', style: TextStyle(color: Colors.grey[600])))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
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
            ],
          ),
        ),
      ),
    );
  }

  int _noteCount(String projectName) {
    return _projects.firstWhere((p) => p.name == projectName, orElse: () => _ProjectData(name: projectName, noteCount: 0)).noteCount;
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
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Color(0xFF00d4ff)))),
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
          color: const Color(0xFF1a1a2e),
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
