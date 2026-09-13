import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/supabase_service.dart';
import 'services/tts_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://eupylqnoiynliqafyiim.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV1cHlscW5vaXlubGlxYWZ5aWltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUyMzkyOTksImV4cCI6MjEwMDgxNTI5OX0.X2xRsM-1t_hiDeolHJVPISJKkgiDqw_2p0EvJIukeiw',
    );

    final supabase = Supabase.instance.client;

    

    debugPrint("✅ Supabase initialized");
  } catch (e) {
    debugPrint("Supabase error: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SupabaseService()),
        ChangeNotifierProvider(create: (_) => ApiService()),
        ChangeNotifierProvider(create: (_) => TtsService()),
      ],
      child: const SilentVoiceApp(),
    ),
  );
}

class SilentVoiceApp extends StatelessWidget {
  const SilentVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
  title: 'SilentVoice',
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    brightness: Brightness.dark,
    primaryColor: const Color(0xFF6C63FF),
    scaffoldBackgroundColor: const Color(0xFF0F0C20),
    useMaterial3: true,
    textTheme: GoogleFonts.interTextTheme(),
  ),
  home: StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, snapshot) {
      final session = Supabase.instance.client.auth.currentSession;

      if (session == null) {
        return const LoginScreen();
      }

      return const HomeScreen();
    },
  ),
);
  }
}