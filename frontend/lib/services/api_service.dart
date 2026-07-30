import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class PredictionResult {
  final String? gesture;
  final double confidence;
  final bool handDetected;

  PredictionResult({
    required this.gesture,
    required this.confidence,
    required this.handDetected,
  });

  factory PredictionResult.empty() {
    return PredictionResult(
      gesture: null,
      confidence: 0.0,
      handDetected: false,
    );
  }

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      gesture: json['gesture'] as String?,
      confidence: (json['confidence'] as num).toDouble(),
      handDetected: json['hand_detected'] as bool? ?? false,
    );
  }
}

class ApiService extends ChangeNotifier {
  // Default URL is 10.0.2.2 for Android emulator to connect to localhost of host machine
  // Or localhost for iOS Simulator or web
  //the FASTAPI conector
  // Or localhost for iOS Simulator or web
  String _baseUrl = (kIsWeb || 
      defaultTargetPlatform == TargetPlatform.windows || 
      defaultTargetPlatform == TargetPlatform.macOS || 
      defaultTargetPlatform == TargetPlatform.linux)
    ? 'https://gesture-api-service.salmonsky-9e942d8d.centralindia.azurecontainerapps.io'
    : 'http://10.0.2.2:8000';


  bool _isConnecting = false;
  String? _errorMessage;

  String get baseUrl => _baseUrl;
  bool get isConnecting => _isConnecting;
  String? get errorMessage => _errorMessage;

  void updateBaseUrl(String newUrl) {
    // Basic sanitization
    var sanitized = newUrl.trim();
    if (!sanitized.startsWith('http://') && !sanitized.startsWith('https://')) {
      sanitized = 'http://$sanitized';
    }
    _baseUrl = sanitized;
    notifyListeners();
  }

  /// Sends a JPEG frame to the backend `/predict` endpoint
  Future<PredictionResult> predictFrame(List<int> jpegBytes) async {
    _isConnecting = true;
    _errorMessage = null;

    try {
      final uri = Uri.parse('$_baseUrl/predict');
      
      // Create multipart request
      final request = http.MultipartRequest('POST', uri);
      
      // Add compressed JPEG image as a file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          jpegBytes,
          filename: 'frame.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 5),
      );
      
      final response = await http.Response.fromStream(streamedResponse);

      _isConnecting = false;
      notifyListeners();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PredictionResult.fromJson(data);
      } else {
        _errorMessage = 'Server error (${response.statusCode}): ${response.reasonPhrase}';
        return PredictionResult.empty();
      }
    } catch (e) {
      _isConnecting = false;
      _errorMessage = 'Connection failed. Verify API is running at $_baseUrl';
      notifyListeners();
      return PredictionResult.empty();
    }
  }

  /// Check server health status
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/health')).timeout(
        const Duration(seconds: 2),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}