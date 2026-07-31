// lib/core/services/lens_service.dart
//
// NOVA X Visual Search — Google Lens via server-proxy URL (correct approach)
//
// ── WHY THE PREVIOUS APPROACH FAILED ─────────────────────────────────────
//   The HTML-injection approach used flutter_inappwebview's loadData() to
//   serve a page that fetch()-POSTed an image to lens.google.com.
//   Android WebView gives loadData() pages a "null" origin — meaning any
//   fetch() to an external domain (including lens.google.com) is cross-origin
//   and blocked by CORS. There is no workaround; this is an Android security
//   constraint that cannot be overridden with baseUrl.
//
// ── THE CORRECT APPROACH ──────────────────────────────────────────────────
//   1. Pick image (camera or gallery) in Dart
//   2. Upload the image to OUR server via Dio multipart POST
//      → Server saves it and returns a public HTTPS URL
//   3. Navigate the WebView to:
//      https://lens.google.com/uploadbyurl?url=<encoded_public_url>
//   4. Google Lens fetches the image from our server server-side
//      → No CORS, no null-origin, no WebView injection needed
//      → Works identically to how every mobile browser does reverse image search
//
// ── FALLBACK ──────────────────────────────────────────────────────────────
//   If the server upload fails (network error, server down), we navigate
//   directly to https://lens.google.com so the user can upload manually.
//   This is always better than showing an error screen.
//
// ── CONTRACT WITH CALLER ─────────────────────────────────────────────────
//   getSearchUrl() returns:
//     • A lens.google.com/uploadbyurl?url=... string on success
//     • 'https://lens.google.com' string on fallback (server error)
//     • null if the user cancelled the image picker
//
//   Caller simply does:
//     BrowserView(initialQuery: url)
//   No htmlContent, no loadData(), no special handling needed.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nova_x/core/services/api_service.dart';

class LensService {
  static final _picker = ImagePicker();

  /// Server endpoint that accepts a multipart image and returns a public URL.
  static const String _uploadEndpoint =
      '${ApiService.baseUrl}/api/v1/visual-search/upload';

  /// Fallback URL — opens Google Lens so user can upload manually.
  static const String _lensFallback = 'https://lens.google.com';

  // ── Pick image from camera ───────────────────────────────────────────────
  static Future<File?> pickFromCamera() async {
    try {
      final xfile = await _picker.pickImage(
        source:       ImageSource.camera,
        imageQuality: 85,
        maxWidth:     1280,
        maxHeight:    1280,
      );
      return xfile == null ? null : File(xfile.path);
    } catch (_) { return null; }
  }

  // ── Pick image from gallery ──────────────────────────────────────────────
  static Future<File?> pickFromGallery() async {
    try {
      final xfile = await _picker.pickImage(
        source:       ImageSource.gallery,
        imageQuality: 85,
        maxWidth:     1280,
        maxHeight:    1280,
      );
      return xfile == null ? null : File(xfile.path);
    } catch (_) { return null; }
  }

  // ── Upload image to NOVA X server ────────────────────────────────────────
  // Returns the public HTTPS URL of the saved image, or null on failure.
  static Future<String?> _uploadToServer(File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: 'nova_x_search.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      final response = await Dio().post<Map<String, dynamic>>(
        _uploadEndpoint,
        data: formData,
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout:    const Duration(seconds: 20),
          responseType:   ResponseType.json,
        ),
      );

      final url = response.data?['url'] as String?;
      if (url != null && url.startsWith('https://')) return url;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Main entry point ─────────────────────────────────────────────────────
  // Returns the URL to navigate BrowserView to, or null if user cancelled.
  static Future<String?> getSearchUrl({required bool fromCamera}) async {
    // Step 1: Pick image
    final file = fromCamera ? await pickFromCamera() : await pickFromGallery();
    if (file == null) return null; // user cancelled — return null, not fallback

    // Step 2: Upload to server
    final publicUrl = await _uploadToServer(file);

    if (publicUrl == null) {
      // Server upload failed — open Lens homepage so user can try manually
      return _lensFallback;
    }

    // Step 3: Build Google Lens uploadbyurl search URL
    // Google Lens fetches the image from our server and shows visual results
    return 'https://lens.google.com/uploadbyurl?url=${Uri.encodeComponent(publicUrl)}';
  }
}
