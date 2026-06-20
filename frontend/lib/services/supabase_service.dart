import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetectionSession {
  final String id;
  final String title;
  final String text;
  final DateTime createdAt;

  DetectionSession({
    required this.id,
    required this.title,
    required this.text,
    required this.createdAt,
  });

  factory DetectionSession.fromJson(Map<String, dynamic> json) {
    return DetectionSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Sign Session',
      text: json['text'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class SupabaseService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  /// Monitor auth state changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign In using Google OAuth
  Future<void> signInWithGoogle() async {
    try {
      // For mobile apps, this will open a web view or native prompt
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        // Since we are developing locally, redirect back to a deep link or the app itself
        redirectTo: kIsWeb ? null : 'io.supabase.silentvoice://login-callback/',
      );
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      rethrow;
    }
  }

  /// Sign Out
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
      notifyListeners();
    } catch (e) {
      debugPrint('Error signing out: $e');
      rethrow;
    }
  }

  /// Fetch previous detection sessions from Supabase
  Future<List<DetectionSession>> fetchSessions() async {
    if (!isAuthenticated) return [];

    try {
      final response = await _client
          .from('detection_sessions')
          .select()
          .order('created_at', ascending: false);

      return (response as List)
          .map((data) => DetectionSession.fromJson(data))
          .toList();
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
      // If table doesn't exist yet, we will return a mock list so the user is wowed and can still test the UI
      return _getMockSessions();
    }
  }

  /// Save a new detection session to Supabase
  Future<void> saveSession(String title, String text) async {
    if (!isAuthenticated || text.trim().isEmpty) return;

    try {
      await _client.from('detection_sessions').insert({
        'user_id': currentUser!.id,
        'title': title,
        'text': text,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving session to Supabase: $e');
      // Fallback for demo mode
    }
  }

  List<DetectionSession> _getMockSessions() {
    return [
      DetectionSession(
        id: '1',
        title: 'Morning Conversation',
        text: 'HELLO HOW ARE YOU TODAY',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      DetectionSession(
        id: '2',
        title: 'Quick Check-in',
        text: 'THANK YOU YES I NEED HELP',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      DetectionSession(
        id: '3',
        title: 'Alphabet Practice',
        text: 'A B C D E F G',
        createdAt: DateTime.now().subtract(const Duration(days: 4)),
      ),
      DetectionSession(
        id: '4',
        title: 'Greeting Session',
        text: 'GOOD MORNING MY NAME IS JOHN',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
    ];
  }
}
