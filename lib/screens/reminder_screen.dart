import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import '../models/reminder.dart';
import '../services/reminder_service.dart';
import 'note_detail_screen.dart';

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> with TickerProviderStateMixin {
  late List<_ReminderNode> nodes;
  late AnimationController _controller;
  late AnimationController _burstController;
  double _time = 0;
  String? _firedNode;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _controller.addListener(_updatePhysics);
    
    _burstController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _burstController.addListener(() {
      if (_burstController.value > 0.8 && _firedNode != null) {
        setState(() => _firedNode = null);
      }
    });
    
    _loadReminders();
    
    Timer.periodic(const Duration(seconds: 30), (_) {
      _checkReminders();
    });
  }

  Future<void> _checkReminders() async {
    await ReminderService.checkAndFire();
    await _loadReminders();
  }

  Future<void> _loadReminders() async {
    final reminders = await ReminderService.loadReminders();
    final padding = 120.0;
    
    if (reminders.isEmpty) {
      nodes = [];
      setState(() {});
      return;
    }
    
    nodes = reminders.asMap().entries.map((e) {
      final isDue = e.value.shouldFire;
      return _ReminderNode(
        id: e.value.id,
        title: e.value.title,
        dateTime: e.value.dateTime,
        isWeekly: e.value.isWeekly,
        dayOfWeek: e.value.dayOfWeek,
        isDue: isDue,
        x: padding + (e.key % 3) * 150,
        y: padding + (e.key ~/ 3) * 120,
      );
    }).toList();
    
    setState(() {});
  }

  void _updatePhysics() {
    _time += 0.016;
    if (nodes.isEmpty) return;
    
    final centerX = MediaQuery.of(context).size.width / 2;
    final centerY = MediaQuery.of(context).size.height / 2;
    
    for (var i = 0; i < nodes.length; i++) {
      final dx = centerX - nodes[i].x;
      final dy = centerY - nodes[i].y;
      nodes[i].vx += dx * 0.001;
      nodes[i].vy += dy * 0.001;
      nodes[i].vx *= 0.95;
      nodes[i].vy *= 0.95;
      nodes[i].x += nodes[i].vx;
      nodes[i].y += nodes[i].vy;
    }
    
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _burstController.dispose();
    super.dispose();
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
        title: const Text('Reminders', style: TextStyle(color: Color(0xFF00d4ff), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF00ff88)),
            onPressed: _addReminder,
          ),
        ],
      ),
      body: nodes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alarm_off, color: Colors.grey[600], size: 64),
                  const SizedBox(height: 16),
                  Text('No reminders', style: TextStyle(color: Colors.grey[600], fontSize: 18)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _addReminder,
                    child: const Text('Add one', style: TextStyle(color: Color(0xFF00ff88))),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: _ReminderPainter(nodes: nodes, firedNode: _firedNode, time: _time),
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton(
                    backgroundColor: const Color(0xFF00ff88),
                    onPressed: _addReminder,
                    child: const Icon(Icons.add, color: Color(0xFF0a0a0f)),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _addReminder() async {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(hours: 1));
    bool isWeekly = false;
    int? selectedDay;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Reminder', style: TextStyle(color: Color(0xFF00ff88))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Reminder title',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)),
                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ff88))),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Weekly', style: TextStyle(color: Colors.grey)),
                  Switch(
                    value: isWeekly,
                    activeColor: const Color(0xFF00ff88),
                    onChanged: (v) => setDialogState(() => isWeekly = v),
                  ),
                ],
              ),
              if (isWeekly) ...[
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: selectedDay,
                  hint: const Text('Day', style: TextStyle(color: Colors.grey)),
                  dropdownColor: const Color(0xFF1a1a2e),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Monday', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 2, child: Text('Tuesday', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 3, child: Text('Wednesday', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 4, child: Text('Thursday', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 5, child: Text('Friday', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 6, child: Text('Saturday', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 7, child: Text('Sunday', style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (v) => setDialogState(() => selectedDay = v),
                ),
              ],
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(selectedDate),
                    );
                    if (time != null) {
                      setDialogState(() {
                        selectedDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                      });
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2d2d44)),
                child: Text(
                  isWeekly 
                      ? 'Time: ${selectedDate.hour}:${selectedDate.minute.toString().padLeft(2, '0')}'
                      : 'Date: ${selectedDate.day}/${selectedDate.month} ${selectedDate.hour}:${selectedDate.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  final reminder = Reminder(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleController.text,
                    dateTime: selectedDate,
                    isWeekly: isWeekly,
                    dayOfWeek: isWeekly ? selectedDay : null,
                  );
                  ReminderService.addReminder(reminder);
                  Navigator.pop(ctx);
                  _loadReminders();
                }
              },
              child: const Text('Add', style: TextStyle(color: Color(0xFF00ff88))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderNode {
  String id;
  String title;
  DateTime dateTime;
  bool isWeekly;
  int? dayOfWeek;
  bool isDue;
  double x;
  double y;
  double vx;
  double vy;

  _ReminderNode({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.isWeekly,
    this.dayOfWeek,
    this.isDue = false,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
  });
}

class _ReminderPainter extends CustomPainter {
  final List<_ReminderNode> nodes;
  final String? firedNode;
  final double time;

  _ReminderPainter({required this.nodes, this.firedNode, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final node in nodes) {
      final isFiring = node.isDue || firedNode == node.id;
      
      if (isFiring) {
        final pulse = (math.sin(time * 10) + 1) / 2;
        canvas.drawCircle(
          Offset(node.x, node.y),
          50 + pulse * 20,
          Paint()
            ..color = const Color(0xFF00ff88).withOpacity(0.3)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          Offset(node.x, node.y),
          40 + pulse * 15,
          Paint()
            ..color = const Color(0xFF00ff88).withOpacity(0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      
      canvas.drawCircle(
        Offset(node.x, node.y),
        30,
        Paint()
          ..color = node.isDue ? const Color(0xFF00ff88) : const Color(0xFF00d4ff)
          ..style = PaintingStyle.fill,
      );
      
      final titleTp = TextPainter(
        text: TextSpan(
          text: node.title.length > 12 ? '${node.title.substring(0, 10)}..' : node.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      titleTp.layout();
      titleTp.paint(canvas, Offset(node.x - titleTp.width / 2, node.y + 35));
      
      final timeStr = node.isWeekly 
          ? _dayName(node.dayOfWeek ?? 1)
          : '${node.dateTime.day}/${node.dateTime.month}';
      final timeTp = TextPainter(
        text: TextSpan(
          text: timeStr,
          style: TextStyle(
            color: node.isDue ? const Color(0xFF00ff88) : Colors.grey[400],
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      timeTp.layout();
      timeTp.paint(canvas, Offset(node.x - timeTp.width / 2, node.y + 50));
    }
  }
  
  String _dayName(int day) {
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[day];
  }

  @override
  bool shouldRepaint(covariant _ReminderPainter oldDelegate) => true;
}