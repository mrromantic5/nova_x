// lib/core/services/lens_service.dart
//
// NOVA X Visual Search — Base64 JSON → PHP proxy → Google (v5, definitive)
//
// ── WHY THIS VERSION WORKS WHERE OTHERS DIDN'T ───────────────────────────
//
//   All previous server-upload attempts (v2, v4) failed because cPanel shared
//   hosting commonly has `file_uploads = Off` in php.ini, making $_FILES
//   always empty. Multipart form uploads to PHP simply don't work in this
//   environment without hosting changes.
//
//   v5 BYPASSES this entirely:
//     • Image is read into memory in Dart and base64-encoded
//     • Sent to our server as a plain JSON body: {"image": "<base64>"}
//     • PHP receives it via php://input (always works — no file_uploads needed)
//     • PHP decodes it, writes to sys_get_temp_dir() (always writable)
//     • PHP curl POSTs the temp file to Google as a CURLFile
//     • Google returns 302 → PHP extracts the URL → returns JSON to Flutter
//     • Flutter navigates WebView to google.com/search?tbs=sbi:... ✅
//
// ── FALLBACK ─────────────────────────────────────────────────────────────
//   If the server call fails for any reason, opens Google Images so the
//   user can upload manually — always better than a dead screen.

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nova_x/core/services/api_service.dart';

class LensService {
  static final _picker = ImagePicker();

  static const String _proxyEndpoint =
      '${ApiService.baseUrl}/api/v1/visual-search/proxy';

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

  // ── Send base64 image to proxy → get Google results URL ─────────────────
  static Future<String?> _proxySearch(File imageFile) async {
    try {
      // Read image bytes and base64-encode
      final bytes  = await imageFile.readAsBytes();
      final b64    = base64Encode(bytes);

      final response = await Dio().post<Map<String, dynamic>>(
        _proxyEndpoint,
        data: {'image': b64},                    // plain JSON — no file upload
        options: Options(
          contentType: 'application/json',
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout:    const Duration(seconds: 30),
          responseType:   ResponseType.json,
          validateStatus: (s) => s != null && s < 600,
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

    final resultsUrl = await _proxySearch(file);
    return resultsUrl ?? _fallback;
  }
}
