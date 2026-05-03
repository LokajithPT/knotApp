import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:io';
import '../models/note.dart';
import '../services/knot_service.dart';
import 'graph_screen.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  final String? filePath;
  final Project? project;

  const NoteDetailScreen({super.key, required this.note, this.filePath, this.project});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController _contentController;
  bool _hasChanges = false;
  bool _showToolbar = false;
  bool _viewMode = true;
  List<String> _files = [];

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.note.content);
    _contentController.addListener(_onChanged);
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final projectPath = widget.filePath?.substring(0, widget.filePath!.lastIndexOf('/'));
    if (projectPath != null) {
      final dir = Directory(projectPath);
      if (await dir.exists()) {
        final files = await dir.list().where((e) => e is File && e.path.endsWith('.md'))
            .map((e) => e.path.split('/').last.replaceAll('.md', '')).toList();
        setState(() { _files = files; });
      }
    }
  }

  void _onChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _insertText(String text, {bool wrapSelection = false}) {
    final selection = _contentController.selection;
    if (wrapSelection && selection.start != selection.end) {
      final selectedText = _contentController.text.substring(selection.start, selection.end);
      final newText = text.replaceAll('X', selectedText);
      _contentController.text = _contentController.text.replaceRange(selection.start, selection.end, newText);
      _contentController.selection = TextSelection.collapsed(offset: selection.start + newText.length);
    } else if (wrapSelection) {
      final newText = text.replaceAll('X', '');
      final pos = selection.start;
      _contentController.text = _contentController.text.substring(0, pos) + newText + _contentController.text.substring(pos);
      _contentController.selection = TextSelection.collapsed(offset: pos + newText.indexOf('X') + 1);
    } else {
      final pos = selection.start;
      _contentController.text = _contentController.text.substring(0, pos) + text + _contentController.text.substring(pos);
      _contentController.selection = TextSelection.collapsed(offset: pos + text.length);
    }
    setState(() => _hasChanges = true);
  }

  void _showLinkPicker() {
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
            const Text('Insert Link', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.link, color: Color(0xFF7b2cbf)),
              title: const Text('Wiki Link [[note]]', style: TextStyle(color: Color(0xFFe0e0e0))),
              onTap: () { Navigator.pop(ctx); _showFilePicker(false); },
            ),
            ListTile(
              leading: const Icon(Icons.link_off, color: Color(0xFFff006e)),
              title: const Text('Inter-Project [[project:note]]', style: TextStyle(color: Color(0xFFe0e0e0))),
              onTap: () { Navigator.pop(ctx); _showProjectPicker(); },
            ),
          ],
        ),
      ),
    );
  }

  void _showFilePicker(bool isInterProject) {
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files found', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFFff006e)),
      );
      return;
    }
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
            const Text('Select Note', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _files.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.description, color: Color(0xFF00d4ff)),
                  title: Text(_files[index], style: const TextStyle(color: Color(0xFFe0e0e0))),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isInterProject) {
                      _insertText('[[project:${_files[index]}]]');
                    } else {
                      _insertText('[[${_files[index]}]]');
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProjectPicker() async {
    final projects = await KnotService.getProjects();
    if (projects.isEmpty || !mounted) return;
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
            const Text('Select Project', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...projects.map((proj) => ListTile(
              leading: const Icon(Icons.folder, color: Color(0xFF9d4edd)),
              title: Text(proj, style: const TextStyle(color: Color(0xFFe0e0e0))),
              onTap: () async {
                Navigator.pop(ctx);
                final projNotes = await KnotService.loadProject(proj);
                if (!mounted) return;
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF1a1a2e),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (ctx2) => Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notes in $proj', style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: projNotes.notes.length,
                            itemBuilder: (context, i) => ListTile(
                              leading: const Icon(Icons.description, color: Color(0xFF00d4ff)),
                              title: Text(projNotes.notes[i].name, style: const TextStyle(color: Color(0xFFe0e0e0))),
                              onTap: () { Navigator.pop(ctx2); _insertText('[[$proj:${projNotes.notes[i].name}]]'); },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildFormattedText(String content) {
    final wikiLinkPattern = RegExp(r'\[\[(\w+)\]\]');
    final interProjectLinkPattern = RegExp(r'\[\[(\w+):(\w+)\]\]');
    
    final blocks = <Widget>[];
    final lines = content.split('\n');
    
    for (var line in lines) {
      if (line.startsWith('# ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line.substring(2), style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 28, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('## ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(line.substring(3), style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 24, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('### ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line.substring(4), style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 20, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('#### ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line.substring(5), style: const TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('- ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Text('  • ', style: TextStyle(color: Color(0xFFe0e0e0), fontSize: 16)),
              Expanded(child: _buildClickableText(line.substring(2))),
            ],
          ),
        ));
      } else {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _buildClickableText(line),
        ));
      }
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }
  
  Widget _buildClickableText(String text) {
    final spans = <TextSpan>[];
    var currentIndex = 0;
    
    final wikiPattern = RegExp(r'\[\[(\w+)\]\]');
    final interPattern = RegExp(r'\[\[(\w+):(\w+)\]\]');
    final combinedPattern = RegExp(r'\[\[(\w+)(?::(\w+))?\]\]');
    
    for (final match in combinedPattern.allMatches(text)) {
      if (match.start > currentIndex) {
        var plainText = text.substring(currentIndex, match.start);
        plainText = plainText.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!);
        plainText = plainText.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!);
        spans.add(TextSpan(text: plainText, style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 16, height: 1.5)));
      }
      
      final project = match.group(2);
      final target = match.group(1) ?? '';
      
      if (project != null && target.isNotEmpty) {
        spans.add(TextSpan(
          text: '[[$project:$target]]',
          style: const TextStyle(color: Color(0xFFff006e), fontWeight: FontWeight.w500),
          recognizer: TapGestureRecognizer()..onTap = () => _navigateToLink(project, target),
        ));
      } else if (target.isNotEmpty) {
        spans.add(TextSpan(
          text: '[[$target]]',
          style: const TextStyle(color: Color(0xFF7b2cbf), fontWeight: FontWeight.w500),
          recognizer: TapGestureRecognizer()..onTap = () => _navigateToNote(target),
        ));
      }
      currentIndex = match.end;
    }
    
    if (currentIndex < text.length) {
      var remaining = text.substring(currentIndex);
      remaining = remaining.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!);
      remaining = remaining.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!);
      spans.add(TextSpan(text: remaining, style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 16, height: 1.5)));
    }
    
    return RichText(text: TextSpan(children: spans));
  }
  
  void _navigateToNote(String noteName) async {
    Note note;
    Project? proj;
    
    if (widget.project != null) {
      note = widget.project!.notes.firstWhere((n) => n.name == noteName, orElse: () => Note(name: noteName, content: '', preview: '', tags: []));
      proj = widget.project;
    } else {
      final projectPath = widget.filePath?.substring(0, widget.filePath!.lastIndexOf('/'));
      if (projectPath != null) {
        final projectName = projectPath.split('/').last;
        proj = await KnotService.loadProject(projectName);
        note = proj.notes.firstWhere((n) => n.name == noteName, orElse: () => Note(name: noteName, content: '', preview: '', tags: []));
      } else {
        return;
      }
    }
    
    if (note.filePath != null && await File(note.filePath!).exists()) {
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note, filePath: note.filePath, project: proj)));
    }
  }

  Future<List<Note>> _getBacklinks() async {
    Project? proj;
    if (widget.project != null) {
      proj = widget.project;
    } else if (widget.filePath != null) {
      final projectPath = widget.filePath!.substring(0, widget.filePath!.lastIndexOf('/'));
      final projectName = projectPath.split('/').last;
      proj = await KnotService.loadProject(projectName);
    }
    
    if (proj == null) return [];
    
    final backlinks = <Note>[];
    final currentName = widget.note.name;
    
    for (final note in proj.notes) {
      if (note.name == currentName) continue;
      final content = note.content;
      if (content.contains('[[$currentName]]')) {
        backlinks.add(note);
      }
    }
    return backlinks;
  }

  void _navigateToLink(String project, String noteName) async {
    try {
      final proj = await KnotService.loadProject(project);
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => GraphScreen(project: proj)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Note not found: $noteName', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFff006e)),
        );
      }
    }
  }

  Future<void> _save() async {
    if (widget.filePath != null) {
      final content = _contentController.text;
      await File(widget.filePath!).writeAsString(content);
      setState(() => _hasChanges = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF00d4ff), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF00d4ff)), onPressed: () => Navigator.pop(context)),
        title: Text(widget.note.name, style: const TextStyle(color: Color(0xFF00d4ff))),
        actions: [
          IconButton(
            icon: Icon(_viewMode ? Icons.edit : Icons.visibility, color: const Color(0xFF00d4ff)),
            onPressed: () => setState(() => _viewMode = !_viewMode),
          ),
          if (_hasChanges && !_viewMode) IconButton(icon: const Icon(Icons.save, color: Color(0xFF00d4ff)), onPressed: _save),
        ],
      ),
      body: _viewMode
          ? FutureBuilder<List<Note>>(
              future: _getBacklinks(),
              builder: (context, snapshot) {
                final backlinks = snapshot.data ?? [];
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFormattedText(_contentController.text),
                      if (backlinks.isNotEmpty) ...[
                        const SizedBox(height: 30),
                        const Divider(color: Color(0xFF2d2d44)),
                        const Padding(
                          padding: EdgeInsets.only(top: 16, bottom: 8),
                          child: Text('Linked from', style: TextStyle(color: Color(0xFF7b2cbf), fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                        ...backlinks.map((note) => ListTile(
                          leading: const Icon(Icons.arrow_back, color: Color(0xFF7b2cbf), size: 20),
                          title: Text(note.name, style: const TextStyle(color: Color(0xFF00d4ff))),
                          dense: true,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note, filePath: note.filePath, project: widget.project))),
                        )),
                      ],
                    ],
                  ),
                );
              },
            )
          : Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: _showToolbar ? 60 : 0,
                  child: _showToolbar ? Container(
                    color: const Color(0xFF1a1a2e),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _toolButton('H1', () => _insertText('# ')),
                          _toolButton('H2', () => _insertText('## ')),
                          _toolButton('H3', () => _insertText('### ')),
                          _toolButton('B', () => _insertText('**X**', wrapSelection: true), bold: true),
                          _toolButton('I', () => _insertText('*X*', wrapSelection: true), italic: true),
                          _toolButton('•', () => _insertText('- ')),
                          _toolButton('[[', _showLinkPicker),
                          const VerticalDivider(color: Color(0xFF2d2d44), width: 20),
                          _toolButton('H4', () => _insertText('#### ')),
                          _toolButton('"', () => _insertText('"X"', wrapSelection: true)),
                          _toolButton('`', () => _insertText('`X`', wrapSelection: true)),
                        ],
                      ),
                    ),
                  ) : const SizedBox(),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    child: TextField(
                      controller: _contentController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 16, height: 1.5),
                      decoration: const InputDecoration(hintText: 'Start writing...', hintStyle: TextStyle(color: Color(0xFF666666)), border: InputBorder.none),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: !_viewMode ? FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFF1a1a2e),
        onPressed: () => setState(() => _showToolbar = !_showToolbar),
        child: Icon(_showToolbar ? Icons.unfold_less : Icons.unfold_more, color: const Color(0xFF00d4ff)),
      ) : null,
    );
  }

  Widget _toolButton(String label, VoidCallback onPressed, {bool bold = false, bool italic = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Material(
        color: const Color(0xFF2d2d44),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label, style: TextStyle(
              color: const Color(0xFF00d4ff),
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            )),
          ),
        ),
      ),
    );
  }
}