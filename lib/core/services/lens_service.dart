// lib/core/services/lens_service.dart
//
// NOVA X Visual Search — Fixed approach
//
// WHY the old approach failed:
//   Uploading with Dio (separate HTTP context) + opening redirect URL in WebView
//   caused Google to show "Image not associated with your account" because the
//   upload session and the viewing session were different HTTP contexts.
//
// NEW APPROACH:
//   1. Pick image with image_picker
//   2. Convert to base64
//   3. Generate a self-contained HTML page with JavaScript that uploads the
//      image FROM WITHIN the WebView using fetch()
//   4. Open this HTML in BrowserView with baseUrl=google.com (same-origin,
//      no CORS issues, WebView cookies included)
//   5. JS fetch() follows the Google redirect automatically in the WebView

import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class LensService {
  static final _picker = ImagePicker();

  // ── Pick image from camera ─────────────────────────────────────────────────
  static Future<File?> pickFromCamera() async {
    try {
      final xfile = await _picker.pickImage(
        source:       ImageSource.camera,
        imageQuality: 80,
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
        imageQuality: 80,
        maxWidth:     1280,
        maxHeight:    1280,
      );
      return xfile == null ? null : File(xfile.path);
    } catch (_) { return null; }
  }

  // ── Generate search HTML ───────────────────────────────────────────────────
  //
  // Returns a self-contained HTML string that, when loaded in BrowserView
  // with baseUrl='https://www.google.com', performs the image upload and
  // automatically redirects to Google Image Search results.
  //
  // Loading with baseUrl=google.com means:
  //   • The fetch() to /searchbyimage/upload is same-origin (no CORS block)
  //   • The WebView's Google cookies are included in the request
  //   • Google correctly associates the upload with the WebView session
  static Future<String?> buildSearchPage({required bool fromCamera}) async {
    final file = fromCamera ? await pickFromCamera() : await pickFromGallery();
    if (file == null) return null;  // user cancelled

    final bytes    = await file.readAsBytes();
    final b64      = base64Encode(bytes);

    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NOVA X Visual Search</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#07101E;color:#F1F5F9;font-family:-apple-system,BlinkMacSystemFont,sans-serif;
     display:flex;flex-direction:column;align-items:center;justify-content:center;
     min-height:100vh;padding:32px;text-align:center;gap:16px}
.icon{width:72px;height:72px;background:linear-gradient(135deg,#00D4FF,#7C4DFF);
      border-radius:20px;display:flex;align-items:center;justify-content:center;
      font-size:32px;box-shadow:0 0 30px rgba(0,212,255,.3)}
h2{font-size:20px;font-weight:700;color:#fff}
p{font-size:13px;color:#94A3B8;max-width:280px;line-height:1.5}
.bar{width:240px;height:4px;background:#1E293B;border-radius:4px;overflow:hidden}
.fill{height:100%;background:linear-gradient(90deg,#00D4FF,#7C4DFF);border-radius:4px;
      animation:load 2.5s ease-in-out infinite}
@keyframes load{0%{width:0%}50%{width:80%}100%{width:100%}}
.err{color:#FF5252;font-size:13px;margin-top:8px}
a{color:#00D4FF;text-decoration:none;background:#1E293B;padding:12px 28px;
  border-radius:14px;border:1px solid rgba(0,212,255,.3);font-size:14px;font-weight:600;
  display:inline-block;margin-top:8px}
</style>
</head>
<body>
<div class="icon">🔍</div>
<h2>Visual Search</h2>
<p id="msg">Uploading image and searching…</p>
<div class="bar"><div class="fill"></div></div>
<script>
(async function(){
  try {
    // Decode base64 image
    const b64="$b64";
    const bin=atob(b64);
    const arr=new Uint8Array(bin.length);
    for(let i=0;i<bin.length;i++) arr[i]=bin.charCodeAt(i);
    const blob=new Blob([arr],{type:"image/jpeg"});

    // Upload to Google Image Search (same-origin because baseUrl=google.com)
    const fd=new FormData();
    fd.append("encoded_image",blob,"nova_x_search.jpg");
    fd.append("image_content","");
    fd.append("hl","en");

    const res=await fetch("/searchbyimage/upload",{method:"POST",body:fd});

    if(res.url && res.url.length>30) {
      // Success — navigate to results
      document.getElementById("msg").textContent="Found! Loading results…";
      window.location.href=res.url;
    } else {
      throw new Error("Unexpected response from Google");
    }
  } catch(e){
    document.querySelector(".bar").style.display="none";
    document.getElementById("msg").innerHTML=
      '<span class="err">Could not search automatically.</span>';
    document.body.insertAdjacentHTML("beforeend",
      '<a href="https://images.google.com">Open Google Images →</a>');
  }
})();
</script>
</body>
</html>''';
  }
}
