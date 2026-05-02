import 'package:flutter/material.dart';
import 'dart:io';
import '../models/note.dart';
import '../services/knot_service.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  final String? filePath;

  const NoteDetailScreen({super.key, required this.note, this.filePath});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController _contentController;
  bool _hasChanges = false;
  bool _showToolbar = false;
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
              onTap: () {
                Navigator.pop(ctx);
                _showFilePicker(false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_off, color: Color(0xFFff006e)),
              title: const Text('Inter-Project [[project:note]]', style: TextStyle(color: Color(0xFFe0e0e0))),
              onTap: () {
                Navigator.pop(ctx);
                _showProjectPicker();
              },
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
    if (projects.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No projects found', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFFff006e)),
        );
      }
      return;
    }
    if (!mounted) return;
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
                              onTap: () {
                                Navigator.pop(ctx2);
                                _insertText('[[$proj:${projNotes.notes[i].name}]]');
                              },
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
          if (_hasChanges) IconButton(icon: const Icon(Icons.save, color: Color(0xFF00d4ff)), onPressed: _save),
        ],
      ),
      body: Column(
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
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFF1a1a2e),
        onPressed: () => setState(() => _showToolbar = !_showToolbar),
        child: Icon(_showToolbar ? Icons.unfold_less : Icons.unfold_more, color: const Color(0xFF00d4ff)),
      ),
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