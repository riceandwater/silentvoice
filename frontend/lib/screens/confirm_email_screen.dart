import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import 'home_screen.dart';

/// Flowchart step: Supabase sends Email Verification Link
/// -> user clicks the link in their inbox
/// -> this screen catches the redirect on http://localhost:3000
/// -> Verify Email -> Create Profile -> Home
///
/// IMPORTANT: In the Supabase dashboard, under
/// Authentication -> URL Configuration, the Site URL (and Redirect
/// URLs allow-list) must include http://localhost:3000 exactly,
/// or Supabase will refuse to redirect back to this listener.
class ConfirmEmailScreen extends StatefulWidget {
  final String email;

  const ConfirmEmailScreen({super.key, required this.email});

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  static const int _listenPort = 3000;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _serverSub;

  bool _completing = false;
  bool _resending = false;
  String? _errorMessage;

  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _serverSub?.cancel();
    _server?.close(force: true);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _startListening() async {
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _listenPort,
        shared: true,
      );
      _server = server;

      _serverSub = server.listen((HttpRequest request) async {
        final uri = request.uri;
        final code = uri.queryParameters['code'];
        final error = uri.queryParameters['error'];
        final errorDescription = uri.queryParameters['error_description'];

        request.response.headers.contentType = ContentType.html;

        if (code != null) {
          request.response.write(_htmlPage(
            title: "Email confirmed",
            message:
                "You can close this tab and return to SilentVoice.",
          ));
          await request.response.close();
          await _completeWithCode(code);
        } else if (error != null) {
          request.response.write(_htmlPage(
            title: "Confirmation failed",
            message: errorDescription ?? error,
          ));
          await request.response.close();

          if (mounted) {
            setState(() {
              _errorMessage =
                  (errorDescription ?? error).replaceAll('+', ' ');
            });
          }
        } else {
          request.response.write(_htmlPage(
            title: "SilentVoice",
            message: "Waiting for confirmation…",
          ));
          await request.response.close();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              "Couldn't start local listener on port $_listenPort. "
              "Make sure no other app is using that port.\n$e";
        });
      }
    }
  }

  String _htmlPage({required String title, required String message}) {
    return """
<!DOCTYPE html>
<html>
  <head><title>$title</title></head>
  <body style="font-family: sans-serif; text-align:center; padding-top: 80px;">
    <h2>$title</h2>
    <p>$message</p>
  </body>
</html>
""";
  }

  Future<void> _completeWithCode(String code) async {
    if (_completing) return;
    setState(() {
      _completing = true;
      _errorMessage = null;
    });

    final supabase = Provider.of<SupabaseService>(context, listen: false);

    try {
      // Verify Email -> Create Profile (handled inside the service)
      await supabase.completeEmailConfirmation(code);

      await _serverSub?.cancel();
      await _server?.close(force: true);

      if (!mounted) return;

      // -> Home
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _completing = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _startResendCooldown() {
    setState(() => _resendCooldown = 30);

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown -= 1);
      }
    });
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0) return;

    setState(() => _resending = true);

    final supabase = Provider.of<SupabaseService>(context, listen: false);

    try {
      await supabase.resendConfirmationEmail(widget.email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Confirmation email resent.")),
      );

      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff0F0C20),
                  Color(0xff17142E),
                  Color(0xff06040A),
                ],
              ),
            ),
          ),

          Positioned(
            top: -80,
            left: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xff6C63FF).withOpacity(.25),
                    blurRadius: 120,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.05),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withOpacity(.08),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xff6C63FF).withOpacity(.15),
                            ),
                            child: Icon(
                              _completing
                                  ? Icons.hourglass_top_outlined
                                  : Icons.mark_email_unread_outlined,
                              size: 52,
                              color: const Color(0xff8C86FF),
                            ),
                          ),

                          const SizedBox(height: 25),

                          Text(
                            _completing
                                ? "Confirming…"
                                : "Check your inbox",
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            _completing
                                ? "Finishing sign up for ${widget.email}"
                                : "We sent a confirmation link to\n${widget.email}\n\nClick it to finish signing up. This screen will move on automatically.",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white54,
                            ),
                          ),

                          if (_errorMessage != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.redAccent.withOpacity(.3),
                                ),
                              ),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.redAccent.shade100,
                                ),
                              ),
                            ),
                          ],

                          if (_completing) ...[
                            const SizedBox(height: 24),
                            const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ],

                          const SizedBox(height: 20),

                          TextButton(
                            onPressed: (_resending || _resendCooldown > 0)
                                ? null
                                : _resend,
                            child: Text(
                              _resendCooldown > 0
                                  ? "Resend link in ${_resendCooldown}s"
                                  : "Didn't get an email? Resend",
                              style: GoogleFonts.poppins(
                                color: const Color(0xff8C86FF),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}