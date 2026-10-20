// lib/features/ai/services/nova_media_store.dart
//
// Photos in NOVA AI chats (uploaded photos, screenshots, web page captures).
//
//  • The image files stay on this phone, in NOVA X's own storage:
//    <app documents>/nova_media/<chat id>/<message id>_<n>.jpg
//  • A chat message refers to them with a marker at the start of its text:
//      [PHOTOS:chat_1/m1_0.jpg,chat_1/m1_1.jpg]What does this say?
//    Chat history synced to the server carries only this marker and the text
//    (never the image), so on another phone the chat shows "Photo is on your
//    other phone".
//  • Deleting a chat deletes its photos.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// A web page captured in the browser ("Ask NOVA about this page").
class NovaPageCapture {
  const NovaPageCapture({required this.image, required this.title, required this.url, required this.text});

  final Uint8List image;
  final String title;
  final String url;

  /// Visible text of the page (untrusted content; only sent with the question).
  final String text;
}

/// A photo ready to send (resized on the phone).
class NovaPickedPhoto {
  const NovaPickedPhoto(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

class NovaMediaStore {
  NovaMediaStore._();

  static const int maxPhotos = 3;

  /// The server accepts about 2 MB per image; photos are resized well below.
  static const int maxBytes = 2 * 1024 * 1024;

  /// All photos of one message together (the NOVA AI service accepts ≈ 4 MB).
  static const int maxTotalBytes = 4 * 1024 * 1024;

  static const int maxSide = 1280;

  static final RegExp _marker = RegExp(r'^\[PHOTOS:([^\]\n]{0,1000})\]');
  static final RegExp _validRel = RegExp(r'^[A-Za-z0-9_-]{1,64}/[A-Za-z0-9_-]{1,80}\.(?:jpg|png|webp)$');

  // ── Message text (pure, tested) ────────────────────────────────────────

  /// Photo references and the text of a message.
  static ({List<String> photos, String text}) split(String content) {
    final m = _marker.firstMatch(content);
    if (m == null) return (photos: const <String>[], text: content);
    final photos = m
        .group(1)!
        .split(',')
        .map((p) => p.trim())
        .where(isValidRef)
        .take(maxPhotos)
        .toList();
    return (photos: photos, text: content.substring(m.end).trim());
  }

  static bool hasPhotos(String content) => split(content).photos.isNotEmpty;

  static String join(List<String> photos, String text) {
    final refs = photos.where(isValidRef).take(maxPhotos).toList();
    if (refs.isEmpty) return text;
    return '[PHOTOS:${refs.join(',')}]$text';
  }

  /// What the text-only AI sees for a message with photos.
  static String forAi(String content) {
    final s = split(content);
    if (s.photos.isEmpty) return content;
    final n = s.photos.length;
    final note = n == 1 ? '(I shared a photo.)' : '($n photos shared.)';
    return s.text.isEmpty ? note : '$note ${s.text}';
  }

  static bool isValidRef(String ref) => _validRel.hasMatch(ref) && !ref.contains('..');

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Image type from the file's first bytes, or null if not JPEG/PNG/WebP.
  static String? mimeOf(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  static String _ext(String mime) => switch (mime) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };

  // ── Files on the phone ─────────────────────────────────────────────────

  static String? _rootPath;

  /// Call once before showing photos ([pathOf] needs it).
  static Future<void> init() async {
    if (_rootPath != null) return;
    final docs = await getApplicationDocumentsDirectory();
    _rootPath = '${docs.path}/nova_media';
  }

  /// The file for a reference (null before [init] or for invalid references).
  static File? fileOf(String ref) {
    final root = _rootPath;
    if (root == null || !isValidRef(ref)) return null;
    return File('$root/$ref');
  }

  /// Saves a photo of a message; returns its reference.
  static Future<String> save(String chatId, String messageId, int index, Uint8List bytes) async {
    await init();
    final mime = mimeOf(bytes) ?? 'image/jpeg';
    final ref = '${_safe(chatId)}/${_safe(messageId)}_$index.${_ext(mime)}';
    final file = File('${_rootPath!}/$ref');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return ref;
  }

  /// Reads saved photos for sending again (missing ones are skipped).
  static Future<List<NovaPickedPhoto>> load(List<String> refs) async {
    await init();
    final out = <NovaPickedPhoto>[];
    for (final ref in refs.take(maxPhotos)) {
      final f = fileOf(ref);
      if (f == null || !await f.exists()) continue;
      final bytes = await f.readAsBytes();
      final mime = mimeOf(bytes);
      if (mime != null && bytes.length <= maxBytes) out.add(NovaPickedPhoto(bytes, mime));
    }
    return out;
  }

  /// Deletes every photo of a chat (when the chat is deleted).
  static Future<void> deleteChat(String chatId) async {
    try {
      await init();
      final dir = Directory('${_rootPath!}/${_safe(chatId)}');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // best effort
    }
  }

  // ── Picking photos ─────────────────────────────────────────────────────

  static final ImagePicker _picker = ImagePicker();

  /// Camera (one photo) or gallery (up to [max]); resized on the phone.
  /// Returns an empty list when the user cancels. Throws [NovaPhotoException].
  static Future<List<NovaPickedPhoto>> pick({required bool camera, int max = maxPhotos}) async {
    final List<XFile> files;
    try {
      if (camera) {
        final f = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: maxSide.toDouble(),
          maxHeight: maxSide.toDouble(),
          imageQuality: 82,
        );
        files = f == null ? const [] : [f];
      } else {
        files = await _picker.pickMultiImage(
          maxWidth: maxSide.toDouble(),
          maxHeight: maxSide.toDouble(),
          imageQuality: 82,
        );
      }
    } catch (_) {
      throw const NovaPhotoException("The camera or gallery couldn't be opened. Check NOVA X's permissions.");
    }
    final out = <NovaPickedPhoto>[];
    var skipped = 0;
    for (final f in files.take(max)) {
      try {
        final bytes = await File(f.path).readAsBytes();
        final mime = mimeOf(bytes);
        if (mime == null || bytes.length > maxBytes) {
          skipped++;
          continue;
        }
        out.add(NovaPickedPhoto(bytes, mime));
      } catch (_) {
        skipped++;
      }
    }
    if (out.isEmpty && skipped > 0) {
      throw const NovaPhotoException('That photo type isn\'t supported. Use a JPEG, PNG or WebP photo.');
    }
    return out;
  }

  /// Copies a saved photo to the phone's gallery (Pictures/NOVA X, Android 10+).
  static Future<bool> saveToGallery(String ref) async {
    final f = fileOf(ref);
    if (f == null || !await f.exists()) return false;
    try {
      return await const MethodChannel('com.tlyfe.nova_x/nova')
              .invokeMethod<bool>('saveImageToGallery', {'path': f.path}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static String base64Of(Uint8List bytes) => base64Encode(bytes);
}

class NovaPhotoException implements Exception {
  const NovaPhotoException(this.message);
  final String message;

  @override
  String toString() => message;
}
