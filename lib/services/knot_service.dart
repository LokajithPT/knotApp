import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';

class KnotService {
  static String? _knotDir;

  static Future<String> getKnotDir() async {
    if (_knotDir != null) return _knotDir!;
    
    final home = Platform.environment['HOME'];
    if (home != null) {
      _knotDir = '$home/.KnotNotes';
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _knotDir = '${appDir.path}/.KnotNotes';
    }
    
    final dir = Directory(_knotDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    return _knotDir!;
  }

  static Future<List<String>> getProjects() async {
    final knotDir = await getKnotDir();
    final dir = Directory(knotDir);
    final projects = <String>[];
    
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = entity.path.split('/').last;
        if (!name.startsWith('.')) {
          projects.add(name);
        }
      }
    }
    
    return projects;
  }

  static Future<int> getNoteCount(String projectName) async {
    final knotDir = await getKnotDir();
    final projectPath = '$knotDir/$projectName';
    final dir = Directory(projectPath);
    
    if (!await dir.exists()) return 0;
    
    int count = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        count++;
      }
    }
    return count;
  }

  static Future<Project> loadProject(String projectName) async {
    final knotDir = await getKnotDir();
    final projectPath = '$knotDir/$projectName';
    final dir = Directory(projectPath);
    
    if (!await dir.exists()) {
      throw Exception('Project not found: $projectName');
    }
    
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
        if (noteFiles.containsKey(target)) {
          links.add(Link(source: source, target: target));
        }
      }
      
      final interLinks = RegExp(r'\[\[(\w+):(\w+)\]\]').allMatches(content);
      for (final match in interLinks) {
        final project = match.group(1)!;
        final target = match.group(2)!;
        links.add(Link(
          source: source,
          target: target,
          isInterProject: true,
          interProject: project,
        ));
      }
    }
    
    return Project(
      name: projectName,
      path: projectPath,
      notes: notes,
      links: links,
    );
  }
}