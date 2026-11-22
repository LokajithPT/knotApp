import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/settings_service.dart';
import 'services/sms_receiver.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.load();
  await _requestSmsPermissions();
  await SmsReceiverService.init();
  runApp(const KnotApp());
}

Future<void> _requestSmsPermissions() async {
  final status = await Permission.sms.status;
  if (!status.isGranted) {
    await Permission.sms.request();
  }
}

class KnotApp extends StatelessWidget {
  const KnotApp({super.key});

  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Knot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a0f),
        primaryColor: const Color(0xFF00d4ff),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00d4ff),
          secondary: Color(0xFFff006e),
          surface: Color(0xFF1a1a2e),
        ),
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}
