import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../services/tts_service.dart';
import '../utils/image_utils.dart';

/// `camera_windows` does not implement `startImageStream` (frame-by-frame
/// access), so on Windows desktop we fall back to polling `takePicture()`
/// on a timer instead of subscribing to the raw image stream.
bool get _isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isStreaming = false;
  
  // Frame rate throttling variables
  bool _isProcessingFrame = false;
  DateTime _lastFrameProcessedTime = DateTime.now();
  static const int _frameIntervalMs = 300; // ~3.3 frames per second - optimal speed/bandwidth balance

  // Windows-only: polling timer used instead of startImageStream (see note above)
  Timer? _captureTimer;
  
  // Translation state
  String _currentPrediction = '';
  double _currentConfidence = 0.0;
  bool _handDetected = false;
  final List<String> _detectedWords = [];
  String _lastConfirmedGesture = '';
  
  // UI States
  bool _isMuted = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showError('No cameras found on this device.');
        return;
      }
      
      // Select the front-facing camera for gesture translation
      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // We use ResolutionPreset.medium (usually 720p or 480p) to optimize bandwidth and speed
      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: kIsWeb
            ? ImageFormatGroup.jpeg
            : defaultTargetPlatform == TargetPlatform.iOS
                ? ImageFormatGroup.bgra8888
                : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });

      _startFrameStream();
    } catch (e) {
      _showError('Camera initialization failed: $e');
    }
  }

  void _startFrameStream() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isStreaming = true;
    });

    if (_isWindowsDesktop) {
      // camera_windows doesn't implement startImageStream, so poll
      // takePicture() on a timer instead.
      _startWindowsPolling();
    } else {
      _startMobileImageStream();
    }
  }

  void _startMobileImageStream() {
    _controller!.startImageStream((CameraImage image) async {
      // 1. Throttle frame rate (skip frames to avoid overloading API)
      final now = DateTime.now();
      if (_isProcessingFrame ||
          now.difference(_lastFrameProcessedTime).inMilliseconds < _frameIntervalMs) {
        return;
      }

      _isProcessingFrame = true;
      _lastFrameProcessedTime = now;

      try {
        // 2. Convert CameraImage to compressed JPEG bytes directly (optimized downsampling)
        final jpegBytes = ImageUtils.convertCameraImageToJpeg(image);

        if (jpegBytes.isEmpty || !mounted) {
          _isProcessingFrame = false;
          return;
        }

        // 3. Send JPEG to FastAPI backend
        final apiService = Provider.of<ApiService>(context, listen: false);
        final result = await apiService.predictFrame(jpegBytes);

        if (!mounted) return;
        _handlePredictionResult(result);
      } catch (e) {
        debugPrint("Error streaming camera frame: $e");
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  /// Windows fallback: `camera_windows` doesn't support `startImageStream`,
  /// so instead we snap a still photo on a timer. `takePicture()` already
  /// returns a JPEG-encoded file, so we skip ImageUtils entirely here.
  void _startWindowsPolling() {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: _frameIntervalMs),
      (timer) async {
        if (_isProcessingFrame ||
            _controller == null ||
            !_controller!.value.isInitialized ||
            _controller!.value.isTakingPicture) {
          return;
        }

        _isProcessingFrame = true;

        try {
          final xFile = await _controller!.takePicture();
          final jpegBytes = await xFile.readAsBytes();

          if (jpegBytes.isEmpty || !mounted) {
            _isProcessingFrame = false;
            return;
          }

          final apiService = Provider.of<ApiService>(context, listen: false);
          final result = await apiService.predictFrame(jpegBytes);

          if (!mounted) return;
          _handlePredictionResult(result);
        } catch (e) {
          debugPrint("Error capturing/sending Windows frame: $e");
        } finally {
          _isProcessingFrame = false;
        }
      },
    );
  }

  void _handlePredictionResult(PredictionResult result) {
    setState(() {
      _handDetected = result.handDetected;
      _currentConfidence = result.confidence;

      if (result.gesture != null) {
        _currentPrediction = result.gesture!;

        // Check if this is a newly stabilized gesture (prevents multiple triggers of the same word)
        if (_currentPrediction != _lastConfirmedGesture) {
          _lastConfirmedGesture = _currentPrediction;
          _detectedWords.add(_currentPrediction);

          // Speak aloud using Text-to-Speech if not muted
          if (!_isMuted) {
            final ttsService = Provider.of<TtsService>(context, listen: false);
            ttsService.speak(_currentPrediction);
          }
        }
      } else {
        // No gesture detected (hand not present or low confidence)
        _currentPrediction = '';
        _lastConfirmedGesture = '';
      }
    });
  }

  void _stopFrameStream() {
    _captureTimer?.cancel();
    _captureTimer = null;
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    setState(() {
      _isStreaming = false;
      _currentPrediction = '';
      _handDetected = false;
    });
  }

  Future<void> _saveCurrentSession() async {
    if (_detectedWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot save empty session.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    
    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      final textResult = _detectedWords.join(' ');
      final title = 'Session - ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      
      await supabaseService.saveSession(title, textResult);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back to Home Screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _clearSession() {
    setState(() {
      _detectedWords.clear();
      _currentPrediction = '';
      _lastConfirmedGesture = '';
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _stopFrameStream();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0C20),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Real-time Translate",
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _isMuted ? Colors.redAccent : Colors.white70,
            ),
            onPressed: () {
              setState(() {
                _isMuted = !_isMuted;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Camera Viewport
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera preview
                  if (_isCameraInitialized && _controller != null)
                    Center(
                      child: Transform.scale(
                        scale: 1.0, // Adjust sizing if needed
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: CameraPreview(_controller!),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Color(0xFF6C63FF)),
                          const SizedBox(height: 16),
                          Text(
                            "Initializing Camera...",
                            style: GoogleFonts.inter(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),

                  // API Error Banner Overlay
                  if (apiService.errorMessage != null)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          apiService.errorMessage!,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  // Target Box guide overlay (Google Meet visual feel)
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: size.width * 0.65,
                      height: size.width * 0.65,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _handDetected
                              ? const Color(0xFF00D2FF).withOpacity(0.8)
                              : Colors.white.withOpacity(0.2),
                          width: 2.0,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),

                  // Predicted Sign Name HUD Overlay
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _handDetected ? "HAND DETECTED" : "NO HAND IN FRAME",
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _handDetected ? const Color(0xFF00D2FF) : Colors.white30,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currentPrediction.isNotEmpty
                                  ? _currentPrediction.toUpperCase()
                                  : "Awaiting gesture...",
                              style: GoogleFonts.outfit(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _currentPrediction.isNotEmpty
                                    ? Colors.greenAccent
                                    : Colors.white54,
                              ),
                            ),
                            if (_currentPrediction.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                "Confidence: ${(_currentConfidence * 100).toStringAsFixed(0)}%",
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white38,
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Translated Text Sheet (Session accumulator)
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1C2A),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Translated Output",
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_detectedWords.isNotEmpty)
                        TextButton(
                          onPressed: _clearSession,
                          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                          child: const Text("Clear"),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Compiled Text Display
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: Text(
                          _detectedWords.isEmpty
                              ? "Perform gestures within the box to compile a sentence. Your word history will appear here..."
                              : _detectedWords.join(' '),
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: _detectedWords.isEmpty ? Colors.white24 : Colors.white,
                            height: 1.5,
                            fontStyle: _detectedWords.isEmpty ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Controls Bar (Save session, Pause translation)
                  Row(
                    children: [
                      // Pause/Resume toggler
                      IconButton(
                        onPressed: () {
                          if (_isStreaming) {
                            _stopFrameStream();
                          } else {
                            _startFrameStream();
                          }
                        },
                        icon: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white.withOpacity(0.06),
                          child: Icon(
                            _isStreaming ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Save Session Button
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving || _detectedWords.isEmpty
                                ? null
                                : _saveCurrentSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 20),
                            label: Text(
                              "Save Translation Session",
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}