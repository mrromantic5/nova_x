// lib/core/services/lens_service.dart
//
// NOVA X Visual Search — PHP Server Proxy approach (definitive fix)
//
// ── COMPLETE HISTORY OF ATTEMPTS ─────────────────────────────────────────
//
//   v1 — HTML injection via loadData():
//     Android WebView gives loadData() pages a "null" origin.
//     fetch() to Google from null-origin = CORS blocked. Unfixable.
//
//   v2 — Server upload + lens.google.com/uploadbyurl:
//     cPanel hosting restrictions caused server uploads to fail silently.
//     Fell through to fallback every time.
//
//   v3 — Direct Dart Dio POST to lens.google.com/v3/upload:
//     Google blocked non-browser clients even with Chrome UA spoofing.
//     response.realUri returned lens.google.com homepage, not results.
//
// ── THE CORRECT DEFINITIVE SOLUTION (v4) ─────────────────────────────────
//
//   Architecture:
//     Flutter → [multipart image] → OUR PHP server
//     PHP server → [curl POST] → images.google.com/searchbyimage/upload
//     Google → [302 redirect] → google.com/search?tbs=sbi:...
//     PHP server → [returns JSON] → { "url": "https://www.google.com/search?tbs=sbi:..." }
//     Flutter → WebView.navigate(url) → EXACT result as originally working
//
//   Why this works:
//     - PHP curl on the server is a real server-side HTTP client
//     - Google trusts server-to-server requests with proper headers
//     - The returned URL is the EXACT google.com/search?tbs=sbi:... URL
//       that was working before — same result page shown in the screenshot
//     - No CORS, no null-origin, no WebView injection needed
//     - The WebView just opens a regular Google search results URL

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nova_x/core/services/api_service.dart';

class LensService {
  static final _picker = ImagePicker();

  // Our PHP proxy endpoint — POSTs image to Google and returns the results URL
  static const String _proxyEndpoint =
      '${ApiService.baseUrl}/api/v1/visual-search/proxy';

  // Fallback: Google Images homepage
  static const String _fallback = 'https://images.google.com';

  // ── Pick image from camera ───────────────────────────────────────────────
  static Future<File?> pickFromCamera() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      return x == null ? null : File(x.path);
    } catch (_) {
      return null;
    }
  }

  // ── Pick image from gallery ──────────────────────────────────────────────
  static Future<File?> pickFromGallery() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      return x == null ? null : File(x.path);
    } catch (_) {
      return null;
    }
  }

  // ── Send image to our PHP proxy, get back the Google results URL ─────────
  static Future<String?> _getResultsUrlViaProxy(File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: 'search.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      final response = await Dio().post<Map<String, dynamic>>(
        _proxyEndpoint,
        data: formData,
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 20),
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200) {
        final url = response.data?['url'] as String?;
        if (url != null && url.startsWith('https://')) return url;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Main entry point ─────────────────────────────────────────────────────
  static Future<String?> getSearchUrl({required bool fromCamera}) async {
    final file = fromCamera ? await pickFromCamera() : await pickFromGallery();
    if (file == null) return null; // user cancelled

    final resultsUrl = await _getResultsUrlViaProxy(file);
    return resultsUrl ?? _fallback;
  }
}
