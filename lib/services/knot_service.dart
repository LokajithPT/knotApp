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

  static Future<Map<String, List<String>>> getAllProjectNotes() async {
    final knotDir = await getKnotDir();
    final dir = Directory(knotDir);
    final result = <String, List<String>>{};
    
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final projectName = entity.path.split('/').last;
        if (!projectName.startsWith('.')) {
          final notes = <String>[];
          await for (final file in entity.list()) {
            if (file is File) {
              if (file.path.endsWith('.md')) {
                notes.add(file.path.split('/').last.replaceAll('.md', ''));
              } else if (file.path.endsWith('.m4a') || file.path.endsWith('.wav') || file.path.endsWith('.webm')) {
                notes.add(file.path.split('/').last.split('.').first);
              }
            }
          }
          result[projectName] = notes;
        }
      }
    }
    return result;
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
        final mdPath = entity.path;
        final name = mdPath.split('/').last.replaceAll('.md', '');
        final voicePath = mdPath.replaceAll('.md', '.m4a');
        if (await File(voicePath).exists()) {
          continue;
        }
        final content = await entity.readAsString();
        noteFiles[name] = content;
        notes.add(Note.fromMarkdown(name, content, entity.path));
      } else if (entity is File && (entity.path.endsWith('.m4a') || entity.path.endsWith('.wav') || entity.path.endsWith('.webm'))) {
        final name = entity.path.split('/').last.split('.').first;
        notes.add(Note.fromVoice(name, entity.path));
      }
    }
    
    for (final entry in noteFiles.entries) {
      final source = entry.key;
      final content = entry.value;
      
      final wikiLinks = RegExp(r'\[\[([^\]]+)\]\]').allMatches(content);
      for (final match in wikiLinks) {
        final target = match.group(1)!;
        if (noteFiles.containsKey(target)) {
          links.add(Link(source: source, target: target));
        }
      }
      
      final interLinks = RegExp(r'\[\[([^\]]+):([^\]]+)\]\]').allMatches(content);
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

  static Future<void> saveNodePositions(String projectName, Map<String, Map<String, double>> positions, {Map<String, bool>? staticNodes}) async {
    final knotDir = await getKnotDir();
    final positionsFile = File('$knotDir/$projectName/.positions.json');
    final dir = Directory('$knotDir/$projectName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final buffer = StringBuffer('{');
    var first = true;
    for (final entry in positions.entries) {
      if (!first) buffer.write(',');
      first = false;
      final isStatic = staticNodes?[entry.key] ?? false;
      buffer.write('"${entry.key.replaceAll('"', '\\"')}":{"x":${entry.value['x']},"y":${entry.value['y']},"static":$isStatic}');
    }
    buffer.write('}');
    await positionsFile.writeAsString(buffer.toString());
  }

  static Future<Map<String, Map<String, double>>?> loadNodePositions(String projectName) async {
    try {
      final knotDir = await getKnotDir();
      final positionsFile = File('$knotDir/$projectName/.positions.json');
      if (!await positionsFile.exists()) return null;
      
      final content = await positionsFile.readAsString();
      if (content.trim() == '{}' || content.trim().isEmpty) return null;
      
      final result = <String, Map<String, double>>{};
      
      final entryPattern = RegExp(r'"([^"]+)":\{"x":([0-9.-]+),"y":([0-9.-]+)(?:,"static":(true|false))?\}');
      for (final match in entryPattern.allMatches(content)) {
        final name = match.group(1)!;
        final x = double.tryParse(match.group(2)!) ?? 0;
        final y = double.tryParse(match.group(3)!) ?? 0;
        result[name] = {'x': x, 'y': y};
      }
      
      return result.isEmpty ? null : result;
    } catch (e) {
      return null;
    }
  }
  
  static Future<Map<String, bool>?> loadStaticNodes(String projectName) async {
    try {
      final knotDir = await getKnotDir();
      final positionsFile = File('$knotDir/$projectName/.positions.json');
      if (!await positionsFile.exists()) return null;
      
      final content = await positionsFile.readAsString();
      if (content.trim() == '{}' || content.trim().isEmpty) return null;
      
      final result = <String, bool>{};
      
      final entryPattern = RegExp(r'"([^"]+)":\{"x":([0-9.-]+),"y":([0-9.-]+),"static":(true|false)\}');
      for (final match in entryPattern.allMatches(content)) {
        final name = match.group(1)!;
        final isStatic = match.group(4) == 'true';
        if (isStatic) result[name] = true;
      }
      
      return result.isEmpty ? null : result;
    } catch (e) {
      return null;
    }
  }
}