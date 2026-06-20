import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img_lib;

class ImageUtils {
  /// Converts a [CameraImage] to a JPEG byte array.
  /// Downsamples the image by a factor of 2 to reduce resolution,
  /// speed up CPU-bound YUV-to-RGB conversion, and minimize network payload.
  static List<int> convertCameraImageToJpeg(CameraImage cameraImage) {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;
      
      // Downsampling factor: 2x downscale (4x pixel reduction)
      const int step = 2;
      final int outWidth = width ~/ step;
      final int outHeight = height ~/ step;
      
      // Create empty image object using the image library (v4 style)
      final img = img_lib.Image(width: outWidth, height: outHeight);

      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        final planeY = cameraImage.planes[0];
        final planeU = cameraImage.planes[1];
        final planeV = cameraImage.planes[2];
        
        final yBuffer = planeY.bytes;
        final uBuffer = planeU.bytes;
        final vBuffer = planeV.bytes;
        
        final int yRowStride = planeY.bytesPerRow;
        final int uRowStride = planeU.bytesPerRow;
        final int vRowStride = planeV.bytesPerRow;
        
        final int? uPixelStride = planeU.bytesPerPixel;
        final int? vPixelStride = planeV.bytesPerPixel;

        if (uPixelStride == null || vPixelStride == null) {
          return [];
        }

        for (int y = 0; y < outHeight; y++) {
          final int srcY = y * step;
          final int uvY = srcY >> 1;
          
          for (int x = 0; x < outWidth; x++) {
            final int srcX = x * step;
            final int uvX = srcX >> 1;
            
            final int yIndex = srcY * yRowStride + srcX;
            final int uIndex = uvY * uRowStride + uvX * uPixelStride;
            final int vIndex = uvY * vRowStride + uvX * vPixelStride;
            
            // Bounds check
            if (yIndex >= yBuffer.length || uIndex >= uBuffer.length || vIndex >= vBuffer.length) {
              continue;
            }
            
            final int yp = yBuffer[yIndex];
            final int up = uBuffer[uIndex];
            final int vp = vBuffer[vIndex];
            
            // Fast integer YUV to RGB conversion
            // R = Y + 1.370705 * (V - 128)
            // G = Y - 0.337633 * (U - 128) - 0.698001 * (V - 128)
            // B = Y + 1.732446 * (U - 128)
            final int rVal = (yp + 1.370705 * (vp - 128)).round().clamp(0, 255);
            final int gVal = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128)).round().clamp(0, 255);
            final int bVal = (yp + 1.732446 * (up - 128)).round().clamp(0, 255);
            
            img.setPixelRgb(x, y, rVal, gVal, bVal);
          }
        }
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        // iOS / Simulators BGRA format
        final bytes = cameraImage.planes[0].bytes;
        
        for (int y = 0; y < outHeight; y++) {
          final int srcY = y * step;
          for (int x = 0; x < outWidth; x++) {
            final int srcX = x * step;
            final int index = (srcY * width + srcX) * 4;
            
            if (index + 3 >= bytes.length) {
              continue;
            }
            
            final int bVal = bytes[index];
            final int gVal = bytes[index + 1];
            final int rVal = bytes[index + 2];
            
            img.setPixelRgb(x, y, rVal, gVal, bVal);
          }
        }
      } else {
        // Fallback for other formats: not supported directly
        debugPrint("Unsupported camera image format group: ${cameraImage.format.group}");
        return [];
      }

      // Encode image to compressed JPEG format
      return img_lib.encodeJpg(img, quality: 75);
    } catch (e) {
      debugPrint("Error converting CameraImage to JPEG: $e");
      return [];
    }
  }
}
