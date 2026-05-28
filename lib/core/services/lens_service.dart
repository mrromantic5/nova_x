// lib/core/services/lens_service.dart
//
// NOVA X Visual Search — works in 3 steps:
//   1. Capture image via device camera or gallery (image_picker)
//   2. POST the image to Google's reverse image search upload endpoint
//   3. Follow the redirect URL → open in NOVA X browser
//
// This is the same mechanism Chrome uses for "Search with Google Lens".
// No API key required. Works for: identifying objects, products,
// landmarks, finding similar images, and reading text in photos.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

class LensService {
  static final _picker = ImagePicker();

  // ── Pick image from camera ─────────────────────────────────────────────────
  static Future<File?> pickFromCamera() async {
    try {
      final xfile = await _picker.pickImage(
        source:        ImageSource.camera,
        imageQuality:  85,
        maxWidth:      1920,
        maxHeight:     1920,
      );
      return xfile == null ? null : File(xfile.path);
    } catch (_) {
      return null;
    }
  }

  // ── Pick image from gallery ────────────────────────────────────────────────
  static Future<File?> pickFromGallery() async {
    try {
      final xfile = await _picker.pickImage(
        source:        ImageSource.gallery,
        imageQuality:  85,
        maxWidth:      1920,
        maxHeight:     1920,
      );
      return xfile == null ? null : File(xfile.path);
    } catch (_) {
      return null;
    }
  }

  // ── Upload image → get Google Image Search result URL ──────────────────────
  //
  // Google's image search upload endpoint accepts a multipart POST and
  // returns a 302 redirect to the search-results page.
  // We extract that URL and open it in the NOVA X browser.
  static Future<String?> getSearchUrl(File imageFile) async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);

      final formData = FormData.fromMap({
        'encoded_image': await MultipartFile.fromFile(
          imageFile.path,
          filename: 'search.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
        'image_content': '',
        'hl': 'en',
      });

      final response = await dio.post(
        'https://www.google.com/searchbyimage/upload',
        data: formData,
        options: Options(
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 11; Mobile) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/124.0.0.0 Mobile Safari/537.36',
            'Referer': 'https://images.google.com',
          },
        ),
      );

      // Google returns 302/303 redirect to results page
      if (response.statusCode == 302 || response.statusCode == 303) {
        String? location = response.headers.value('location');
        if (location != null && !location.startsWith('http')) {
          location = 'https://www.google.com$location';
        }
        return location;
      }

      // Some regions return 200 with a redirect in body — fall back to Lens URL
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Full flow: pick → upload → return URL (or fallback) ───────────────────
  //
  // Returns the Google Image Search URL to open in the browser.
  // Falls back to Google Lens web if upload fails.
  static Future<String?> search({required bool fromCamera}) async {
    final file = fromCamera
        ? await pickFromCamera()
        : await pickFromGallery();
    if (file == null) return null;   // user cancelled

    // Try Google Image Search upload
    final url = await getSearchUrl(file);
    if (url != null) return url;

    // Fallback: open Google Lens web interface
    return 'https://lens.google.com';
  }
}
