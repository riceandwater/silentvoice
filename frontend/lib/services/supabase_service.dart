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

  bool get isAuthenticated => currentUser != null;

  /// True once Supabase has confirmed the user's email address.
  /// Useful for gating navigation to Home after the OTP step.
  bool get isEmailVerified =>
      currentUser?.emailConfirmedAt != null;

  Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  // -------------------------
  // GOOGLE AUTHENTICATION
  // (Temporarily Disabled)
  // -------------------------

  // -------------------------
  // REGISTER
  // -------------------------
  //
  // Per the app flow: Register -> Supabase sends an email OTP ->
  // Verify Email -> Create Profile -> Home.
  //
  // We intentionally do NOT create the `profiles` row here anymore.
  // The username is stashed in the auth user's metadata during
  // signUp, and the actual profile row is created later, once the
  // email has been verified (see `createProfileIfNeeded`).

  // The redirect target our desktop app listens on (see
  // confirm_email_screen.dart, which binds an HttpServer to this
  // exact address). This MUST also be added to Authentication ->
  // URL Configuration -> Redirect URLs in the Supabase dashboard.
  static const String _emailRedirectTo = 'http://localhost:3000';

  Future<void> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: _emailRedirectTo,
        data: {
          'username': username,
        },
      );

      debugPrint("Registration successful. Confirmation email sent.");
      notifyListeners();
    } catch (e) {
      debugPrint("Registration Error:");
      debugPrint(e.toString());
      rethrow;
    }
  }

  // -------------------------
  // COMPLETE EMAIL CONFIRMATION (link-based)
  // -------------------------
  //
  // Called by confirm_email_screen.dart once it catches the redirect
  // from the confirmation link, with the `code` query param Supabase
  // appended to the URL.

  Future<void> completeEmailConfirmation(String code) async {
    try {
      await _client.auth.exchangeCodeForSession(code);

      debugPrint("Email confirmed successfully.");

      // Flowchart: Verify Email -> Create Profile
      await createProfileIfNeeded();

      notifyListeners();
    } catch (e) {
      debugPrint("Email Confirmation Error:");
      debugPrint(e.toString());
      rethrow;
    }
  }

  // -------------------------
  // RESEND CONFIRMATION EMAIL
  // -------------------------

  Future<void> resendConfirmationEmail(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: _emailRedirectTo,
      );
      debugPrint("Confirmation email resent to $email.");
    } catch (e) {
      debugPrint("Resend Confirmation Error:");
      debugPrint(e.toString());
      rethrow;
    }
  }

  // -------------------------
  // CREATE PROFILE
  // -------------------------
  //
  // Called once the user's email is verified. Safe to call more than
  // once (upsert), in case it's ever re-triggered (e.g. app restart
  // mid-flow).

  Future<void> createProfileIfNeeded() async {
    final user = currentUser;

    if (user == null) {
      debugPrint("No authenticated user; skipping profile creation.");
      return;
    }

    final username = (user.userMetadata?['username'] as String?)?.trim();
    final resolvedUsername = (username == null || username.isEmpty)
        ? (user.email?.split('@').first ?? 'user')
        : username;

    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'username': resolvedUsername,
        'email': user.email,
      });

      debugPrint("Profile created/updated successfully.");
    } catch (e) {
      debugPrint("Error creating profile:");
      debugPrint(e.toString());
      rethrow;
    }
  }

  // -------------------------
  // LOGIN
  // -------------------------

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      debugPrint("Login successful.");
      notifyListeners();
    } catch (e) {
      debugPrint("Login Error:");
      debugPrint(e.toString());
      rethrow;
    }
  }

  // -------------------------
  // RESET PASSWORD
  // -------------------------

  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      debugPrint("Password reset email sent.");
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
    debugPrint("========== SAVE SESSION ==========");
    debugPrint("Authenticated: $isAuthenticated");
    debugPrint("Current User: ${currentUser?.id}");
    debugPrint("Text: $text");

    if (!isAuthenticated) {
      debugPrint("User is NOT authenticated");
      return;
    }

    if (text.trim().isEmpty) {
      debugPrint("Text is empty");
      return;
    }

    try {
      await _client.from('gesture_history').insert({
        'user_id': currentUser!.id,
        'gesture': text.trim(),
        'confidence': null,
      });

      debugPrint("✅ Gesture session saved successfully.");
      notifyListeners();
    } catch (e) {
      debugPrint("❌ ERROR SAVING:");
      debugPrint(e.toString());
      rethrow;
    }
  }
}