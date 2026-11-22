import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import '../models/note.dart';
import '../services/knot_service.dart';
import '../services/settings_service.dart';
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
  bool _audioPlayerCollapsed = false;
  List<String> _files = [];
  double _lastEditorSize = 0;
  
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  List<double> _waveform = [];
  List<double> _liveAmplitudes = [];

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController();
    _loadContentFromFile();
    _contentController.addListener(_onChanged);
    _loadFiles();
    _lastEditorSize = SettingsService.settings.editorTextSize;
    if (widget.note.isVoiceNote) {
      _initAudioPlayer();
      _loadVoiceNoteText();
    }
    SettingsService.addListener(_onSettingsChanged);
  }

  Future<void> _loadContentFromFile() async {
    if (widget.filePath != null) {
      final file = File(widget.filePath!);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (mounted && content.isNotEmpty) {
          _contentController.text = content;
        } else if (mounted) {
          _contentController.text = widget.note.content;
        }
      } else if (mounted) {
        _contentController.text = widget.note.content;
      }
    } else if (mounted) {
      _contentController.text = widget.note.content;
    }
  }

  void _onSettingsChanged() {
    final newSize = SettingsService.settings.editorTextSize;
    if (newSize != _lastEditorSize) {
      _lastEditorSize = newSize;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadVoiceNoteText() async {
    if (widget.note.filePath != null && widget.note.isVoiceNote) {
      final textFilePath = widget.note.filePath!.replaceAll('.m4a', '.md');
      final textFile = File(textFilePath);
      if (await textFile.exists()) {
        final textContent = await textFile.readAsString();
        if (mounted && textContent.isNotEmpty) {
          _contentController.text = textContent;
        }
      }
    }
  }

  Future<void> _initAudioPlayer() async {
    _audioPlayer = AudioPlayer();
    await _audioPlayer!.setSourceDeviceFile(widget.note.filePath ?? '');
    final dur = await _audioPlayer!.getDuration();
    if (mounted) setState(() => _duration = dur ?? Duration.zero);
    _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer!.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    await _loadWaveform();
  }

  Future<void> _loadWaveform() async {
    final waveformPath = widget.note.filePath?.replaceAll('.m4a', '.waveform');
    if (waveformPath != null) {
      final file = File(waveformPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = content.split(',').where((s) => s.isNotEmpty).map((s) => double.tryParse(s) ?? 0.3).toList();
        if (mounted) setState(() => _waveform = data);
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _contentController.dispose();
    SettingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final projectPath = widget.filePath?.substring(0, widget.filePath!.lastIndexOf('/'));
    if (projectPath != null) {
      final dir = Directory(projectPath);
      if (await dir.exists()) {
        final fileNames = <String>{};
        await for (final entity in dir.list()) {
          if (entity is File) {
            final path = entity.path;
            final name = path.split('/').last;
            if (path.endsWith('.md')) {
              final mdName = name.replaceAll('.md', '');
              final voicePath = path.replaceAll('.md', '.m4a');
              final voiceExists = await File(voicePath).exists();
              if (!voiceExists) fileNames.add(mdName);
            } else if (path.endsWith('.m4a')) {
              fileNames.add(name.replaceAll('.m4a', ''));
            } else if (_isImageFile(path)) {
              fileNames.add(name);
            }
          }
        }
        setState(() { _files = fileNames.toList(); });
      }
    }
  }

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || 
           lower.endsWith('.png') || lower.endsWith('.gif') ||
           lower.endsWith('.webp') || lower.endsWith('.heic');
  }

  bool _fileIsImage(String name) {
    final lower = name.toLowerCase();
    return lower.contains('.jpg') || lower.contains('.jpeg') || 
           lower.contains('.png') || lower.contains('.gif') ||
           lower.contains('.webp') || lower.contains('.heic');
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

  void _showAllProjectsTree() async {
    final allProjectNotes = await KnotService.getAllProjectNotes();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Project Tree', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: allProjectNotes.length,
                  itemBuilder: (context, index) {
                    final projectName = allProjectNotes.keys.elementAt(index);
                    final notes = allProjectNotes[projectName]!;
                    return ExpansionTile(
                      leading: const Icon(Icons.folder, color: Color(0xFF00d4ff)),
                      title: Text(projectName, style: const TextStyle(color: Color(0xFFe0e0e0), fontWeight: FontWeight.w600)),
                      children: notes.map((noteName) => ListTile(
                        leading: const Icon(Icons.description, color: Color(0xFF7b2cbf), size: 18),
                        title: Text(noteName, style: const TextStyle(color: Color(0xFFe0e0e0))),
                        dense: true,
                        onTap: () {
                          Navigator.pop(ctx);
                          final currentProject = widget.project?.name ?? '';
                          if (currentProject == projectName) {
                            _insertText('[[$noteName]]');
                          } else {
                            _insertText('[[$projectName:$noteName]]');
                          }
                        },
                      )).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
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
      builder: (ctx) {
        final filteredFiles = _files.where((f) => f != widget.note.name && !_fileIsImage(f)).toList();
        
        if (filteredFiles.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: const Center(
              child: Text('No other notes to link', style: TextStyle(color: Color(0xFF666666))),
            ),
          );
        }
        
        return Container(
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
                  itemCount: filteredFiles.length,
                  itemBuilder: (context, index) {
                    final name = filteredFiles[index];
                    final isImg = _fileIsImage(name);
                    return ListTile(
                      leading: Icon(
                        isImg ? Icons.image : Icons.description,
                        color: isImg ? const Color(0xFFffbe0b) : const Color(0xFF00d4ff),
                      ),
                      title: Text(name, style: const TextStyle(color: Color(0xFFe0e0e0))),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (isInterProject) {
                          _insertText('[[project:$name]]');
                        } else {
                          _insertText('[[$name]]');
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showProjectPicker() async {
    final projects = await KnotService.getProjects();
    final currentProject = widget.project?.name ?? '';
    final filteredProjects = projects.where((p) => p != currentProject).toList();
    if (filteredProjects.isEmpty || !mounted) return;
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
            ...filteredProjects.map((proj) => ListTile(
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
    final baseSize = 16 * SettingsService.settings.editorTextSize;
    final accentColors = [const Color(0xFF00d4ff), const Color(0xFFff006e), const Color(0xFF7b2cbf), const Color(0xFF00ff88)];
    final accent = accentColors[SettingsService.settings.accentColorIndex];
    
    final blocks = <Widget>[];
    final lines = content.split('\n');
    
    for (var line in lines) {
      if (line.startsWith('# ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line.substring(2), style: TextStyle(color: accent, fontSize: baseSize * 1.75, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('## ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(line.substring(3), style: TextStyle(color: accent, fontSize: baseSize * 1.5, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('### ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line.substring(4), style: TextStyle(color: accent, fontSize: baseSize * 1.25, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('#### ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line.substring(5), style: TextStyle(color: accent, fontSize: baseSize * 1.125, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('- ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Text('  • ', style: TextStyle(color: const Color(0xFFe0e0e0), fontSize: baseSize)),
              Expanded(child: _buildClickableText(line.substring(2), baseSize)),
            ],
          ),
        ));
      } else if (!RegExp(r'^!\[.*\]\(.+\)$').hasMatch(line)) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _buildClickableText(line, baseSize),
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
  
  Widget _buildClickableText(String text, double baseSize) {
    final spans = <TextSpan>[];
    var currentIndex = 0;
    
    final combinedPattern = RegExp(r'\[\[([^\]]+)(?::([^\]]+))?\]\]');
    
    for (final match in combinedPattern.allMatches(text)) {
      if (match.start > currentIndex) {
        var plainText = text.substring(currentIndex, match.start);
        plainText = plainText.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!);
        plainText = plainText.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!);
        spans.add(TextSpan(text: plainText, style: TextStyle(color: const Color(0xFFe0e0e0), fontSize: baseSize, height: 1.5)));
      }
      
      final project = match.group(2);
      final target = match.group(1) ?? '';
      
      if (project != null && target.isNotEmpty) {
        spans.add(TextSpan(
          text: '@$target@',
          style: const TextStyle(color: Color(0xFFff006e), fontWeight: FontWeight.w500),
          recognizer: TapGestureRecognizer()..onTap = () => _navigateToLink(project, target),
        ));
      } else if (target.isNotEmpty) {
        spans.add(TextSpan(
          text: '@$target',
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
      spans.add(TextSpan(text: remaining, style: TextStyle(color: const Color(0xFFe0e0e0), fontSize: baseSize, height: 1.5)));
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
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1a1a2e),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Open "$noteName"', style: const TextStyle(color: Color(0xFF00d4ff))),
            content: Text('This note is in project "$project". Open the graph and navigate to it?', style: const TextStyle(color: Color(0xFFe0e0e0))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => GraphScreen(project: proj, highlightNote: noteName)));
                },
                child: const Text('Open Graph', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Project not found: $project', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFff006e)),
        );
      }
    }
  }

  Future<void> _save() async {
    if (widget.filePath != null) {
      final content = _contentController.text;
      
      if (widget.note.isVoiceNote && content.isNotEmpty) {
        final textFilePath = widget.filePath!.replaceAll('.m4a', '.md');
        await File(textFilePath).writeAsString(content);
      } else if (!widget.note.isVoiceNote) {
        await File(widget.filePath!).writeAsString(content);
      }
      
      setState(() => _hasChanges = false);
    }
  }

  Future<void> _renameNote() async {
    final controller = TextEditingController(text: widget.note.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Note', style: TextStyle(color: Color(0xFF00d4ff))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'New name',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00d4ff))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Rename', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != widget.note.name) {
      final oldPath = widget.filePath!;
      final dir = oldPath.substring(0, oldPath.lastIndexOf('/'));
      final newPath = '$dir/$newName.${widget.note.isVoiceNote ? 'm4a' : 'md'}';
      
      final oldFile = File(oldPath);
      if (await oldFile.exists()) {
        await oldFile.rename(newPath);
        
        if (widget.note.isVoiceNote) {
          final oldWaveform = oldPath.replaceAll('.m4a', '.waveform');
          final newWaveform = newPath.replaceAll('.m4a', '.waveform');
          final waveformFile = File(oldWaveform);
          if (await waveformFile.exists()) {
            await waveformFile.rename(newWaveform);
          }
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note renamed', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF00d4ff), duration: Duration(seconds: 1)),
          );
          Navigator.pop(context, {'renamed': true, 'newName': newName, 'newPath': newPath});
        }
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
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF00d4ff)), onPressed: () => Navigator.pop(context)),
        title: Text(widget.note.name, style: const TextStyle(color: Color(0xFF00d4ff))),
        actions: [
          if (!widget.note.isVoiceNote)
            IconButton(
              icon: const Icon(Icons.drive_file_rename_outline, color: Color(0xFF00d4ff)),
              onPressed: _renameNote,
            ),
          IconButton(
            icon: Icon(_viewMode ? Icons.edit : Icons.visibility, color: const Color(0xFF00d4ff)),
            onPressed: () => setState(() => _viewMode = !_viewMode),
          ),
          if (_hasChanges && !_viewMode) IconButton(icon: const Icon(Icons.save, color: Color(0xFF00d4ff)), onPressed: _save),
        ],
      ),
      body: widget.note.isVoiceNote
          ? Column(
              children: [
                if (!_audioPlayerCollapsed) _buildAudioPlayer(),
                if (_audioPlayerCollapsed) _buildMiniAudioPlayer(),
                Expanded(child: _viewMode ? _buildViewMode() : _buildEditMode()),
              ],
            )
          : (_viewMode
              ? _buildViewMode()
              : _buildEditMode()),
    );
  }

  Widget _buildAudioPlayer() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF1a1a2e),
      child: Column(
        children: [
          _buildVisualizer(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: const Color(0xFF00ff88), size: 48),
                onPressed: () async {
                  if (_isPlaying) {
                    await _audioPlayer!.pause();
                  } else {
                    await _audioPlayer!.resume();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Slider(
            value: _position.inMilliseconds.toDouble(),
            max: _duration.inMilliseconds.toDouble(),
            activeColor: const Color(0xFF00ff88),
            inactiveColor: const Color(0xFF2d2d44),
            onChanged: (val) async {
              await _audioPlayer!.seek(Duration(milliseconds: val.toInt()));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_position), style: const TextStyle(color: Color(0xFF00ff88), fontSize: 12)),
              Text(_formatDuration(_duration), style: const TextStyle(color: Color(0xFF00ff88), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.expand_less, color: Color(0xFF00d4ff)),
              onPressed: () => setState(() => _audioPlayerCollapsed = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAudioPlayer() {
    return GestureDetector(
      onTap: () => setState(() => _audioPlayerCollapsed = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFF1a1a2e),
        child: Row(
          children: [
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: const Color(0xFF00ff88)),
              onPressed: () async {
                if (_isPlaying) {
                  await _audioPlayer?.pause();
                } else {
                  await _audioPlayer?.resume();
                }
              },
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: const Color(0xFF00ff88),
                  inactiveTrackColor: const Color(0xFF2d2d44),
                  thumbColor: const Color(0xFF00ff88),
                ),
                child: Slider(
                  value: _position.inMilliseconds.toDouble(),
                  max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                  onChanged: (val) async {
                    await _audioPlayer?.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),
            ),
            Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: const TextStyle(color: Color(0xFF00ff88), fontSize: 12),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.expand_more, color: Color(0xFF00d4ff)),
              onPressed: () => setState(() => _audioPlayerCollapsed = false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualizer() {
    final hasWaveform = _waveform.isNotEmpty;
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(20, (i) {
          final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;
          final barProgress = i / 20;
          final isPast = barProgress <= progress;
          
          double height;
          if (hasWaveform) {
            final waveIndex = (i * _waveform.length / 20).floor();
            final waveAmp = waveIndex < _waveform.length ? _waveform[waveIndex] : 0.3;
            height = isPast ? 10.0 + (waveAmp * 50) : 10.0;
          } else {
            final bounce = _isPlaying ? (math.sin(i.toDouble() * 0.5 + DateTime.now().millisecondsSinceEpoch * 0.01) + 1) / 2 : 0.3;
            height = isPast ? 10.0 + (bounce * 40) : 10.0;
          }
          
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 8,
            height: height,
            decoration: BoxDecoration(
              color: isPast ? const Color(0xFF00ff88) : const Color(0xFF2d2d44),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Widget _buildViewMode() {
    return FutureBuilder<List<Note>>(
      future: _getBacklinks(),
      builder: (context, snapshot) {
        final backlinks = snapshot.data ?? [];
        final content = _contentController.text;
        final widgets = _buildContentWithImages(content);
        
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...widgets,
              if (_getTagsFromContent(content).isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _getTagsFromContent(content).map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7b2cbf).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF7b2cbf).withOpacity(0.5)),
                      ),
                      child: Text('#$tag', style: const TextStyle(color: Color(0xFF7b2cbf), fontSize: 12)),
                    )).toList(),
                  ),
                ),
              ],
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
    );
  }

  List<String> _getTagsFromContent(String content) {
    return RegExp(r'#(\w+)').allMatches(content).map((m) => m.group(1)!).toList();
  }

  List<Widget> _buildContentWithImages(String content) {
    final widgets = <Widget>[];
    final lines = content.split('\n');
    final projectPath = widget.filePath?.substring(0, widget.filePath!.lastIndexOf('/')) ?? '';
    final baseSize = 16 * SettingsService.settings.editorTextSize;
    final accentColors = [const Color(0xFF00d4ff), const Color(0xFFff006e), const Color(0xFF7b2cbf), const Color(0xFF00ff88)];
    final accent = accentColors[SettingsService.settings.accentColorIndex];
    
    for (final line in lines) {
      if (RegExp(r'^!\[.*\]\(.+\)$').hasMatch(line)) {
        final match = RegExp(r'^!\[.*\]\((.+)\)$').firstMatch(line);
        if (match != null) {
          final imagePath = match.group(1)!;
          final fullPath = '$projectPath/$imagePath';
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
            child: GestureDetector(
              onTap: () => _showFullScreenImage(fullPath),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(fullPath),
                  width: MediaQuery.of(context).size.width - 40,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2d2d44),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.broken_image, color: Color(0xFF666666)),
                        const SizedBox(width: 8),
                        Text(imagePath, style: const TextStyle(color: Color(0xFF666666))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ));
        }
      } else if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 20, right: 20, top: 20),
          child: Text(line.substring(2), style: TextStyle(color: accent, fontSize: baseSize * 1.75, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 20, right: 20),
          child: Text(line.substring(3), style: TextStyle(color: accent, fontSize: baseSize * 1.5, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 20, right: 20),
          child: Text(line.substring(4), style: TextStyle(color: accent, fontSize: baseSize * 1.25, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('#### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 20, right: 20),
          child: Text(line.substring(5), style: TextStyle(color: accent, fontSize: baseSize * 1.125, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 20, right: 20),
          child: Row(
            children: [
              Text('  • ', style: TextStyle(color: const Color(0xFFe0e0e0), fontSize: baseSize)),
              Expanded(child: _buildClickableText(line.substring(2), baseSize)),
            ],
          ),
        ));
      } else if (line.trim().isNotEmpty && !RegExp(r'^#\w+$').hasMatch(line.trim())) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 20, right: 20),
          child: _buildClickableText(line, baseSize),
        ));
      }
    }
    return widgets;
  }

  void _showFullScreenImage(String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                color: Colors.black.withOpacity(0.9),
                child: Center(
                  child: InteractiveViewer(
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditMode() {
    return Column(
      children: [
        Container(
          height: 56,
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
                _toolButton('link', _showLinkPicker),
                _toolButton('tree', _showAllProjectsTree),
                _toolButton('draw', _showDrawingDialog),
_toolButton('img', _importImage),
                  _toolButton('tag', _addTag),
                  const VerticalDivider(color: Color(0xFF2d2d44), width: 20),
                _toolButton('H4', () => _insertText('#### ')),
                _toolButton('"', () => _insertText('"X"', wrapSelection: true)),
                _toolButton('merm', () => _insertText('`X`', wrapSelection: true)),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _contentController,
              maxLines: null,
              expands: true,
              style: TextStyle(
                color: const Color(0xFFe0e0e0), 
                fontSize: 16 * SettingsService.settings.editorTextSize, 
                height: 1.5
              ),
              decoration: InputDecoration(
                hintText: 'Start writing...', 
                hintStyle: TextStyle(color: const Color(0xFF666666), fontSize: 16 * SettingsService.settings.editorTextSize), 
                border: InputBorder.none
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showDrawingDialog() {
    if (widget.filePath == null) return;
    final projectPath = widget.filePath!.substring(0, widget.filePath!.lastIndexOf('/'));
    
    showDialog(
      context: context,
      builder: (ctx) => _DrawingDialog(
        projectPath: projectPath,
        noteName: widget.note.name,
        onSave: (imagePath) {
          _insertText('\n![drawing]($imagePath)\n');
        },
      ),
    );
  }

  Future<void> _importImage() async {
    if (widget.filePath == null) return;
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null && mounted) {
      final projectPath = widget.filePath!.substring(0, widget.filePath!.lastIndexOf('/'));
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalName = pickedFile.path.split('/').last;
      final extension = originalName.contains('.') ? '.${originalName.split('.').last}' : '.jpg';
      final newName = '${widget.note.name}_img_$timestamp$extension';
      final destPath = '$projectPath/$newName';
      
      await File(pickedFile.path).copy(destPath);
      
      _insertText('\n![image]($newName)\n');
    }
  }

  void _addTag() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Tag', style: TextStyle(color: Color(0xFF00d4ff))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'tag name',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00d4ff))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey[500]))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Add', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (tag != null && tag.isNotEmpty && mounted) {
      final cleanTag = tag.replaceAll('#', '').trim();
      _insertText('#$cleanTag ');
    }
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

class _DrawingDialog extends StatefulWidget {
  final String projectPath;
  final String noteName;
  final Function(String) onSave;

  const _DrawingDialog({
    required this.projectPath,
    required this.noteName,
    required this.onSave,
  });

  @override
  State<_DrawingDialog> createState() => _DrawingDialogState();
}

class _DrawingDialogState extends State<_DrawingDialog> {
  List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  double _strokeWidth = 3.0;
  Color _strokeColor = Colors.white;
  
  final _colors = [
    Colors.white,
    const Color(0xFF00d4ff),
    const Color(0xFFff006e),
    const Color(0xFF00ff88),
    const Color(0xFFffbe0b),
  ];

  void _clear() {
    setState(() {
      _strokes = [];
      _currentStroke = [];
    });
  }

  Future<void> _save() async {
    if (_strokes.isEmpty) return;
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final imagePath = '${widget.projectPath}/${widget.noteName}_drawing_$timestamp.png';
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(400, 300);
    
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1a1a2e),
    );
    
    final paint = Paint()
      ..color = _strokeColor
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    
    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    
    await File(imagePath).writeAsBytes(bytes);
    
    if (mounted) {
      Navigator.pop(context);
      widget.onSave(imagePath.split('/').last);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Draw', style: TextStyle(color: Color(0xFF00d4ff), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              height: 300,
              width: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF0a0a0f),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2d2d44)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onPanStart: (d) => setState(() => _currentStroke = [d.localPosition]),
                  onPanUpdate: (d) => setState(() => _currentStroke.add(d.localPosition)),
                  onPanEnd: (d) => setState(() {
                    _strokes.add(List.from(_currentStroke));
                    _currentStroke = [];
                  }),
                  child: CustomPaint(
                    size: const Size(300, 300),
                    painter: _DrawingPainter(
                      strokes: _strokes,
                      currentStroke: _currentStroke,
                      strokeColor: _strokeColor,
                      strokeWidth: _strokeWidth,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _colors.map((c) => GestureDetector(
                onTap: () => setState(() => _strokeColor = c),
                child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c == _strokeColor ? const Color(0xFF00d4ff) : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: _clear,
                  child: const Text('Clear', style: TextStyle(color: Color(0xFFff006e))),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey[500])),
                ),
                ElevatedButton(
                  onPressed: _strokes.isEmpty ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00d4ff),
                    foregroundColor: const Color(0xFF0a0a0f),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Color strokeColor;
  final double strokeWidth;

  _DrawingPainter({
    required this.strokes,
    required this.currentStroke,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.length >= 2) {
      final currentPath = Path()..moveTo(currentStroke[0].dx, currentStroke[0].dy);
      for (int i = 1; i < currentStroke.length; i++) {
        currentPath.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(currentPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}