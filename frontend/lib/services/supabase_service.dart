import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetectionSession {
  final String id;
  final String title;
  final String text;
  final DateTime createdAt;
  final String? gesture;
  final double? confidence;

  DetectionSession({
    required this.id,
    required this.title,
    required this.text,
    required this.createdAt,
    this.gesture,
    this.confidence,
  });

  factory DetectionSession.fromJson(Map<String, dynamic> json) {
    final gesture = json['gesture'] as String?;

    return DetectionSession(
      id: json['id'].toString(),
      title: json['title'] as String? ??
          (gesture != null ? 'Gesture Detection' : 'Sign Session'),
      text: json['text'] as String? ?? (gesture ?? ''),
      createdAt: DateTime.parse(
        (json['created_at'] ?? json['detected_at']) as String,
      ),
      gesture: gesture,
      confidence: json['confidence'] != null
          ? (json['confidence'] as num).toDouble()
          : null,
    );
  }
}

class SupabaseService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

bool get isAuthenticated {
  final user = currentUser;
  return user != null && !user.isAnonymous;
}

  Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  // -------------------------
  // GOOGLE AUTHENTICATION
  // -------------------------

// -------------------------
// GOOGLE AUTHENTICATION
// -------------------------

Future<void> signInWithGoogle() async {
  try {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.flutter://login-callback',
    );
  } catch (e) {
    debugPrint(e.toString());
    rethrow;
  }
}

  // -------------------------
  // SIGN OUT
  // -------------------------

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
      notifyListeners();
    } catch (e) {
      debugPrint('Error signing out: $e');
      rethrow;
    }
  }

  // -------------------------
  // SAVE INDIVIDUAL GESTURE
  // -------------------------

  Future<void> saveGesture({
    required String gesture,
    required double confidence,
  }) async {
    if (!isAuthenticated) {
      debugPrint('User is not authenticated.');
      return;
    }

    try {
      await _client.from('gesture_history').insert({
        'user_id': currentUser!.id,
        'gesture': gesture,
        'confidence': confidence,
      });

      debugPrint('Gesture saved successfully.');
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving gesture: $e');
      rethrow;
    }
  }

  // -------------------------
  // FETCH GESTURE HISTORY
  // -------------------------

  Future<List<DetectionSession>> fetchSessions() async {
    if (!isAuthenticated) return [];

    try {
      final response = await _client
          .from('gesture_history')
          .select()
          .eq('user_id', currentUser!.id)
          .order('detected_at', ascending: false);

      return (response as List)
          .map((data) => DetectionSession.fromJson(data))
          .toList();
    } catch (e) {
      debugPrint('Error fetching gesture history: $e');
      return [];
    }
  }

  // -------------------------
  // COMPATIBILITY WITH CURRENT UI
  // -------------------------

  Future<void> saveSession(String title, String text) async {
    if (!isAuthenticated || text.trim().isEmpty) return;

    try {
      await _client.from('gesture_history').insert({
        'user_id': currentUser!.id,
        'gesture': text.trim(),
        'confidence': null,
      });

      debugPrint('Gesture session saved successfully.');
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving gesture session: $e');
      rethrow;
    }
  }
}