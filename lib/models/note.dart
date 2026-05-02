class Note {
  final String name;
  final String content;
  final String preview;
  final List<String> tags;
  final String type;
  final String? filePath;

  Note({
    required this.name,
    required this.content,
    required this.preview,
    required this.tags,
    this.type = 'note',
    this.filePath,
  });

  factory Note.fromMarkdown(String name, String content, String? filePath) {
    final tags = RegExp(r'#(\w+)').allMatches(content).map((m) => m.group(1)!).toList();
    final preview = content.length > 100 ? '${content.substring(0, 100)}...' : content;
    return Note(
      name: name,
      content: content,
      preview: preview,
      tags: tags,
      filePath: filePath,
    );
  }
}

class Link {
  final String source;
  final String target;
  final bool isInterProject;
  final String? interProject;

  Link({
    required this.source,
    required this.target,
    this.isInterProject = false,
    this.interProject,
  });
}

class Project {
  final String name;
  final String path;
  final List<Note> notes;
  final List<Link> links;

  Project({
    required this.name,
    required this.path,
    required this.notes,
    required this.links,
  });
}