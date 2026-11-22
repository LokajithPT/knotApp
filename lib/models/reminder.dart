class Reminder {
  final String id;
  final String title;
  final String? noteId;
  final DateTime dateTime;
  final bool isWeekly;
  final int? dayOfWeek;
  bool isActive;
  bool lastFired;

  Reminder({
    required this.id,
    required this.title,
    this.noteId,
    required this.dateTime,
    this.isWeekly = false,
    this.dayOfWeek,
    this.isActive = true,
    this.lastFired = false,
  });

  Reminder copyWith({
    String? id,
    String? title,
    String? noteId,
    DateTime? dateTime,
    bool? isWeekly,
    int? dayOfWeek,
    bool? isActive,
    bool? lastFired,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      noteId: noteId ?? this.noteId,
      dateTime: dateTime ?? this.dateTime,
      isWeekly: isWeekly ?? this.isWeekly,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      isActive: isActive ?? this.isActive,
      lastFired: lastFired ?? this.lastFired,
    );
  }

  bool get shouldFire {
    if (!isActive) return false;
    final now = DateTime.now();
    if (isWeekly && dayOfWeek != null) {
      return now.weekday == dayOfWeek && 
             now.hour == dateTime.hour && 
             now.minute == dateTime.minute &&
             !lastFired;
    }
    return isActive && 
           now.year == dateTime.year && 
           now.month == dateTime.month && 
           now.day == dateTime.day &&
           now.hour == dateTime.hour && 
           now.minute == dateTime.minute &&
           !lastFired;
  }

  DateTime get nextFireTime {
    final now = DateTime.now();
    if (isWeekly && dayOfWeek != null) {
      var fireDate = DateTime(now.year, now.month, now.day, dateTime.hour, dateTime.minute);
      while (fireDate.weekday != dayOfWeek || fireDate.isBefore(now)) {
        fireDate = fireDate.add(const Duration(days: 1));
      }
      return fireDate;
    }
    if (dateTime.isAfter(now)) return dateTime;
    return dateTime;
  }
}