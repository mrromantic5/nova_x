// lib/core/services/lens_service.dart
//
// NOVA X Visual Search — search with a photo through Google Lens.
//
// How it works (v6):
//   • The user takes a photo or picks one; it is resized on the phone
//     (max 1280 px) so the upload is small.
//   • NOVA X opens a browser tab with a tiny local page that hands the photo
//     to Google Lens exactly like a desktop browser's "Search with Google
//     Lens" upload (POST multipart "encoded_image" to lens.google.com).
//   • Google answers with the results page in that tab.
//
// The photo goes straight from the phone to Google — it is not uploaded to
// Tech Lyfe's server (the old server proxy is no longer used).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// The page to open in a browser tab, or why the photo couldn't be used.
class LensSearch {
  const LensSearch({this.html, this.error});

  final String? html;
  final String? error;
}

class LensService {
  LensService._();

  static final ImagePicker _picker = ImagePicker();

  /// Address shown for the Lens tab before Google's results load.
  static const String startUrl = 'https://lens.google.com';

  /// Larger photos are refused (after resizing they are normally < 1 MB).
  static const int maxBytes = 6 * 1024 * 1024;

  /// Returns null when the user cancelled.
  static Future<LensSearch?> prepare({required bool fromCamera}) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
    } catch (_) {
      return const LensSearch(
          error: "The camera or gallery couldn't be opened. Check NOVA X's permissions.");
    }
    if (picked == null) return null;
    try {
      final bytes = await File(picked.path).readAsBytes();
      if (bytes.isEmpty) return const LensSearch(error: "That photo couldn't be read.");
      if (bytes.length > maxBytes) return const LensSearch(error: 'That photo is too large to search.');
      return LensSearch(html: uploadPage(bytes));
    } catch (_) {
      return const LensSearch(error: "That photo couldn't be read.");
    }
  }

  /// Image type from the file's first bytes (JPEG, PNG, WebP or GIF).
  static String mimeOf(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    if (b.length >= 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return 'image/gif';
    return 'image/jpeg';
  }

  /// A self-submitting page that uploads [bytes] to Google Lens from the
  /// browser tab (multipart field "encoded_image").
  static String uploadPage(Uint8List bytes) {
    final mime = mimeOf(bytes);
    final ext = switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };
    final b64 = base64Encode(bytes); // only [A-Za-z0-9+/=]: safe inside a JS string
    return '''<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Google Lens</title>
<style>
html,body{margin:0;height:100%;background:#0b1120;color:#cbd5e1;font-family:Roboto,system-ui,sans-serif}
.box{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;text-align:center;padding:24px;box-sizing:border-box}
.spin{width:36px;height:36px;border:3px solid rgba(0,212,255,.25);border-top-color:#00d4ff;border-radius:50%;animation:s .9s linear infinite}
@keyframes s{to{transform:rotate(360deg)}}
img{max-width:62%;max-height:32vh;border-radius:16px;opacity:.9}
a{color:#00d4ff}
</style></head>
<body><div class="box"><img id="p" alt=""><div class="spin" id="sp"></div><div id="m">Searching with Google Lens…</div></div>
<form id="f" method="POST" enctype="multipart/form-data" style="display:none"><input type="file" name="encoded_image" id="i"></form>
<script>
(function () {
  var b64 = "$b64";
  var mime = "$mime";
  try {
    document.getElementById("p").src = "data:" + mime + ";base64," + b64;
    var bin = atob(b64), n = bin.length, bytes = new Uint8Array(n);
    for (var k = 0; k < n; k++) bytes[k] = bin.charCodeAt(k);
    var file = new File([bytes], "nova_lens.$ext", { type: mime });
    var dt = new DataTransfer();
    dt.items.add(file);
    document.getElementById("i").files = dt.files;
    var form = document.getElementById("f");
    form.action = "https://lens.google.com/v3/upload?ep=ccm&s=&st=" + Date.now();
    setTimeout(function () { form.submit(); }, 150);
  } catch (e) {
    document.getElementById("sp").style.display = "none";
    document.getElementById("m").innerHTML =
      'Google Lens could not be started here.<br><a href="https://lens.google.com/">Open Google Lens</a>';
  }
})();
</script></body></html>''';
  }
}
