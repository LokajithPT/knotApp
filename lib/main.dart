import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'services/knot_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const KnotApp());
}

class KnotApp extends StatelessWidget {
  const KnotApp({super.key});

  @override
  Widget build(BuildContext context) {
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