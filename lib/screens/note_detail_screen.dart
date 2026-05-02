import 'package:flutter/material.dart';
import 'dart:io';
import '../models/note.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  final String? filePath;

  const NoteDetailScreen({super.key, required this.note, this.filePath});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.name);
    _contentController = TextEditingController(text: widget.note.content);
    _titleController.addListener(_onChanged);
    _contentController.addListener(_onChanged);
  }

  void _onChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.filePath != null) {
      final content = _contentController.text;
      await File(widget.filePath!).writeAsString(content);
      setState(() => _hasChanges = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved', style: TextStyle(color: Colors.white)),
            backgroundColor: Color(0xFF00d4ff),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
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
        title: Text(widget.note.name, style: const TextStyle(color: Color(0xFF00d4ff))),
        actions: [
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save, color: Color(0xFF00d4ff)),
              onPressed: _save,
            ),
        ],
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        child: TextField(
          controller: _contentController,
          maxLines: null,
          expands: true,
          style: const TextStyle(color: Color(0xFFe0e0e0), fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Start writing...',
            hintStyle: TextStyle(color: Color(0xFF666666)),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}