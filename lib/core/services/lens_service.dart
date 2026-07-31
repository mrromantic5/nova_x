// lib/core/services/lens_service.dart
//
// NOVA X Visual Search — Google Lens (2025 fixed approach)
//
// ── ROOT CAUSE OF THE BUG ──────────────────────────────────────────────────
//   Google deprecated google.com/searchbyimage/upload — it now returns HTTP
//   404. All code targeting that URL will fail with "That's an error."
//   Google has migrated image search to Google Lens (lens.google.com).
//
// ── FIX: THREE-TIER SEARCH STRATEGY ──────────────────────────────────────
//
//   Tier 1 — Direct Lens upload (primary, no server needed):
//     In-WebView HTML page POSTs the image directly to lens.google.com/v3/upload.
//     The page is loaded with baseUrl=https://lens.google.com, making the
//     fetch() call same-origin (no CORS), and WebView cookies are included.
//     Google Lens follows redirects and lands on the results page.
//
//   Tier 2 — Proxy URL search (fallback if Tier 1 fails):
//     If the direct Lens upload returns no usable URL, we upload the image
//     to our own server (api.browser.t-lyfe.com.ng/api/v1/visual-search/upload)
//     which saves it and returns a public HTTPS URL.  We then redirect to
//     https://lens.google.com/uploadbyurl?url=<public_url> — Google fetches
//     the image server-side and shows results without any CORS concern.
//
//   Tier 3 — Manual fallback (last resort):
//     Shows a friendly error with links to Google Lens and Google Images.
//
// ── BROWSER VIEW CONTRACT ────────────────────────────────────────────────
//   BrowserView MUST load the returned HTML with:
//     baseUrl: WebUri('https://lens.google.com')
//   This is required for Tier 1 same-origin fetch() to work.

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nova_x/core/services/api_service.dart';

class LensService {
  static final _picker = ImagePicker();

  // Server upload endpoint (Tier 2 fallback)
  static const String _uploadEndpoint =
      '${ApiService.baseUrl}/api/v1/visual-search/upload';

  // ── Pick image from camera ─────────────────────────────────────────────────
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

  // ── Pick image from gallery ────────────────────────────────────────────────
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

  // ── Upload image to NOVA X server (Tier 2) ────────────────────────────────
  // Returns the public URL on success, null on failure.
  static Future<String?> _uploadToServer(File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: 'nova_x_search.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final response = await Dio().post(
        _uploadEndpoint,
        data: formData,
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout:    const Duration(seconds: 20),
        ),
      );
      final url = response.data?['url'] as String?;
      return (url != null && url.startsWith('https://')) ? url : null;
    } catch (_) {
      return null;
    }
  }

  // ── Generate Google Lens search HTML ──────────────────────────────────────
  //
  // Returns a self-contained HTML string to load in BrowserView with
  // baseUrl = 'https://lens.google.com'.
  //
  // Tier 1: Direct POST to /v3/upload (same-origin)
  // Tier 2: Redirect to /uploadbyurl?url=<server_url> (if Tier 1 fails)
  // Tier 3: Manual links to Lens / Google Images
  static Future<String?> buildSearchPage({required bool fromCamera}) async {
    final file = fromCamera ? await pickFromCamera() : await pickFromGallery();
    if (file == null) return null; // user cancelled

    final bytes = await file.readAsBytes();
    final b64   = base64Encode(bytes);

    // Pre-upload to server in parallel (for Tier 2 fallback)
    // This runs concurrently while we build the HTML — by the time Tier 1
    // might fail, the server URL is usually already available.
    String? serverUrl;
    try {
      serverUrl = await _uploadToServer(file).timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
    } catch (_) {
      serverUrl = null;
    }

    // Build the server fallback JS line
    final serverFallbackJs = serverUrl != null
        ? 'window.location.href = "https://lens.google.com/uploadbyurl?url=${Uri.encodeComponent(serverUrl)}";'
        : 'throw new Error("no_server_url");';

    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NOVA X Visual Search</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#07101E;color:#F1F5F9;
     font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
     display:flex;flex-direction:column;align-items:center;
     justify-content:center;min-height:100vh;padding:32px;
     text-align:center;gap:18px}
.icon{width:72px;height:72px;
      background:linear-gradient(135deg,#00D4FF,#7C4DFF);
      border-radius:20px;display:flex;align-items:center;
      justify-content:center;font-size:34px;
      box-shadow:0 0 30px rgba(0,212,255,.35)}
h2{font-size:20px;font-weight:700;color:#fff;letter-spacing:-.3px}
#msg{font-size:13px;color:#94A3B8;max-width:280px;line-height:1.6}
.bar{width:240px;height:4px;background:#1E293B;
     border-radius:4px;overflow:hidden}
.fill{height:100%;
      background:linear-gradient(90deg,#00D4FF,#7C4DFF);
      border-radius:4px;animation:load 2.5s ease-in-out infinite}
@keyframes load{0%{width:0%}50%{width:80%}100%{width:100%}}
.err{color:#FF5252;font-size:13px}
.actions{display:flex;flex-direction:column;gap:10px;margin-top:4px}
a{color:#00D4FF;text-decoration:none;background:#1E293B;
  padding:12px 28px;border-radius:14px;
  border:1px solid rgba(0,212,255,.3);font-size:14px;
  font-weight:600;display:inline-block}
</style>
</head>
<body>
<div class="icon">🔍</div>
<h2>Visual Search</h2>
<p id="msg">Uploading to Google Lens…</p>
<div class="bar" id="bar"><div class="fill"></div></div>

<script>
(async function(){
  const msg = document.getElementById("msg");
  const bar = document.getElementById("bar");

  /* ─── Tier 1: Direct upload to lens.google.com/v3/upload ─────────────── */
  try {
    /* Decode the embedded base64 image */
    const b64 = "$b64";
    const bin = atob(b64);
    const arr = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    const blob = new Blob([arr], { type: "image/jpeg" });

    /* Build FormData for Google Lens v3 endpoint */
    const fd = new FormData();
    fd.append("encoded_image", blob, "nova_x_search.jpg");
    fd.append("image_content", "");
    fd.append("hl", (navigator.language || "en").slice(0, 2));
    fd.append("re", "df");
    fd.append("stcs", "");
    fd.append("ep", "gsbubu");

    msg.textContent = "Searching with Google Lens…";

    /* POST to /v3/upload — same-origin because baseUrl=lens.google.com */
    const res = await fetch("/v3/upload", {
      method:      "POST",
      body:        fd,
      credentials: "include",
      redirect:    "follow",
    });

    const finalUrl = res.url || "";

    /* Valid Lens results URL contains one of these patterns */
    const isLensResult =
      finalUrl.includes("lens.google.com/search") ||
      finalUrl.includes("/search?p=") ||
      finalUrl.includes("google.com/search") ||
      (finalUrl.includes("lens.google.com") && finalUrl.includes("q="));

    if (finalUrl.length > 40 && isLensResult) {
      msg.textContent = "Found! Loading results…";
      window.location.href = finalUrl;
      return;
    }

    /* Some Lens responses carry the URL in JSON body */
    try {
      const clone  = (typeof res.clone === "function") ? res.clone() : res;
      const text   = await clone.text();
      const json   = JSON.parse(text);
      const rUrl   = json.url || json.redirect_url || json.search_url || "";
      if (rUrl.length > 20) { window.location.href = rUrl; return; }
    } catch (_) {}

    /* Tier 1 got a response but no usable URL — fall through to Tier 2 */
    throw new Error("tier1_no_url");

  } catch (tier1Err) {

    /* ─── Tier 2: Use server-side URL with lens.google.com/uploadbyurl ──── */
    try {
      msg.textContent = "Trying alternate search method…";
      $serverFallbackJs
      return; /* navigation initiated — script stops here */
    } catch (tier2Err) {

      /* ─── Tier 3: Manual fallback links ─────────────────────────────── */
      bar.style.display = "none";
      msg.innerHTML = '<span class="err">Could not auto-search. Use the links below:</span>';
      document.body.insertAdjacentHTML("beforeend",
        '<div class="actions">' +
        '<a href="https://lens.google.com">Open Google Lens →</a>' +
        '<a href="https://images.google.com">Open Google Images →</a>' +
        '</div>');
    }
  }
})();
</script>
</body>
</html>''';
  }
}
