// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'screens/login_screen.dart';
import 'screens/main_screen.dart'; // Keeping your dashboard!
import 'services/auth_service.dart';
import 'services/profile_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait for scanner app
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    // ---------------------------------------------------------
    // 1. INITIALIZE SUPABASE
    // ---------------------------------------------------------
    await Supabase.initialize(
      url: 'https://fmcakdpeociqovseukic.supabase.co',       // <--- REPLACE WITH YOUR URL
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZtY2FrZHBlb2NpcW92c2V1a2ljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1NTYwMDEsImV4cCI6MjA4MzEzMjAwMX0.Scod-XKDE5V4oSmIebPY6kKJjOLjm9Nco7hxv-Os-hk',  // <--- REPLACE WITH YOUR KEY
    );
    print('✅ Supabase initialized successfully');

    // ---------------------------------------------------------
    // 2. LOAD 4P's HOUSEHOLDS (NEW)
    // ---------------------------------------------------------
    final profileService = ProfileService();
    await profileService.load4PsHouseholds();
    print('✅ 4Ps households loaded: ${profileService.fourPsHouseholdCount}');
    
  } catch (e) {
    print('⚠️ Initialization failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MDRRMO Evacuee Scanner',
      theme: ThemeData(
        // Modern Theme Configuration
        primarySwatch: Colors.blue,
        primaryColor: const Color(0xFF2563EB), // Royal Blue
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50
        useMaterial3: true,
        
        // AppBar Theme
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          iconTheme: IconThemeData(color: Colors.black87),
        ),

        // Input Decoration (Text Fields)
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),

        // Button Theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const AuthChecker(),
    );
  }
}

class AuthChecker extends StatefulWidget {
  const AuthChecker({super.key});

  @override
  State<AuthChecker> createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isLoggedIn = false;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final isAuthenticated = await _authService.isAuthenticated();
      final userName = await _authService.getUsername();
      
      if (mounted) {
        setState(() {
          _isLoggedIn = isAuthenticated;
          _userName = userName;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoggedIn = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleSignOut() async {
    await _authService.logout();
    if (mounted) {
      setState(() {
        _isLoggedIn = false;
        _userName = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading State
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Animated Transition between Login and Main Screen
    return AnimatedSwitcher(
      // The duration of the transition
      duration: const Duration(milliseconds: 800),
      // Smooth easing curves
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      // The Fade + Zoom effect
      transitionBuilder: (Widget child, Animation<double> animation) {
        final scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: scaleAnimation,
            child: child,
          ),
        );
      },
      // The UI to display based on login state
      child: _isLoggedIn
          ? MainScreen(
              key: const ValueKey('main_screen'), 
              userName: _userName,
              onSignOut: _handleSignOut,
            )
          : LoginScreen(
              key: const ValueKey('login_screen'), 
              onLoginSuccess: _checkAuthStatus,
            ),
    );
  }
}