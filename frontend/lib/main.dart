import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/api_service.dart';
import 'services/supabase_service.dart';
import 'services/tts_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase.
  // Wrapped in a try-catch so developers can run the app in Demo Mode
  // without needing a Supabase project set up immediately.
  try {
    await Supabase.initialize(
      url: 'https://placeholder-project.supabase.co', // Replace with your actual Supabase URL
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.placeholder-anon-key', // Replace with your actual Anon Key
    );
    debugPrint("Supabase initialized successfully.");
  } catch (e) {
    debugPrint("Supabase initialization bypassed/failed. App will default to Demo Mode.");
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
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    
    // Choose start screen based on session persistence (30-day login session)
    final Widget startScreen = supabaseService.isAuthenticated 
        ? const HomeScreen() 
        : const LoginScreen();

    return MaterialApp(
      title: 'SilentVoice (Vapp)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: const Color(0xFF0F0C20),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00D2FF),
          background: Color(0xFF0F0C20),
          surface: Color(0xFF1E1C2A),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        useMaterial3: true,
      ),
      home: startScreen,
    );
  }
}
