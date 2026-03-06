// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
import 'home_screen.dart';

class MainScreen extends StatelessWidget {
  final String? userName;
  final VoidCallback onSignOut;

  const MainScreen({
    super.key,
    required this.userName,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    // Since the bottom navigation tabs were removed,
    // MainScreen now directly loads your HomeScreen dashboard.
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: HomeScreen(
        userName: userName,
        onSignOut: onSignOut,
        // You might want to update your HomeScreen to not rely on this, 
        // but setting it to false since it's no longer inside a tab view.
        
      ),
    );
  }
}