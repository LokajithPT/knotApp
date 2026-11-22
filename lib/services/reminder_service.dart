import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/reminder.dart';

class ReminderService {
  static Future<String> getKnotDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final knotDir = '${dir.path}/.KnotNotes';
    final d = Directory(knotDir);
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return knotDir;
  }

  static Future<List<Reminder>> loadReminders() async {
    try {
      final knotDir = await getKnotDir();
      final file = File('$knotDir/.reminders.json');
      if (!await file.exists()) return [];
      
      final content = await file.readAsString();
      if (content.trim() == '{}' || content.trim().isEmpty || content.trim() == '[]') return [];
      
      final reminders = <Reminder>[];
      final entryPattern = RegExp(r'"([^"]+)":\{"title":"([^"]+)","dateTime":"([^"]+)","isWeekly":(true|false),"dayOfWeek":(\d+|null),"isActive":(true|false)\}');
      
      for (final match in entryPattern.allMatches(content)) {
        if (match.groupCount < 6) continue;
        final id = match.group(1) ?? '';
        final title = match.group(2) ?? '';
        if (id.isEmpty || title.isEmpty) continue;
        
        final dateTime = DateTime.tryParse(match.group(3) ?? '') ?? DateTime.now();
        final isWeekly = match.group(4) == 'true';
        final dayStr = match.group(5);
        final dayOfWeek = dayStr != null && dayStr != 'null' ? int.tryParse(dayStr) : null;
        final isActive = match.group(6) == 'true';
        
        reminders.add(Reminder(
          id: id,
          title: title,
          dateTime: dateTime,
          isWeekly: isWeekly,
          dayOfWeek: dayOfWeek,
          isActive: isActive,
        ));
      }
      
      return reminders;
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveReminders(List<Reminder> reminders) async {
    try {
      final knotDir = await getKnotDir();
      
      final file = File('$knotDir/.reminders.json');
      final buffer = StringBuffer('[');
      var first = true;
      
      for (final r in reminders) {
        if (!first) buffer.write(',\n');
        first = false;
        
        buffer.write('{"id":"${r.id}","title":"${r.title}","dateTime":"${r.dateTime.toIso8601String()}","isWeekly":${r.isWeekly},"dayOfWeek":${r.dayOfWeek ?? 'null'},"isActive":${r.isActive}}');
      }
      
      buffer.write(']');
      await file.writeAsString(buffer.toString());
    } catch (e) {
      // ignore
    }
  }

  static Future<void> addReminder(Reminder reminder) async {
    final reminders = await loadReminders();
    reminders.add(reminder);
    await saveReminders(reminders);
  }

  static Future<void> updateReminder(Reminder reminder) async {
    final reminders = await loadReminders();
    final index = reminders.indexWhere((r) => r.id == reminder.id);
    if (index >= 0) {
      reminders[index] = reminder;
      await saveReminders(reminders);
    }
  }

  static Future<void> deleteReminder(String id) async {
    final reminders = await loadReminders();
    reminders.removeWhere((r) => r.id == id);
    await saveReminders(reminders);
  }

  static Future<void> checkAndFire() async {
    final reminders = await loadReminders();
    var fired = false;
    
    for (final r in reminders) {
      if (r.shouldFire) {
        r.lastFired = true;
        fired = true;
      }
    }
    
    if (fired) {
      await saveReminders(reminders);
    }
  }
}