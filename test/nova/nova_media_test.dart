// test/nova/nova_media_test.dart
//
// Photos in NOVA AI chats: how a message refers to its photos (saved on the
// phone only), what the text-only AI sees, file-name safety and image types.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/ai/services/nova_chat_repository.dart';
import 'package:nova_x/features/ai/services/nova_media_store.dart';

void main() {
  group('photo references in messages', () {
    test('join and split round trip', () {
      final content = NovaMediaStore.join(['chat_1/m1_0.jpg', 'chat_1/m1_1.png'], 'What does this say?');
      expect(content, '[PHOTOS:chat_1/m1_0.jpg,chat_1/m1_1.png]What does this say?');
      final parts = NovaMediaStore.split(content);
      expect(parts.photos, ['chat_1/m1_0.jpg', 'chat_1/m1_1.png']);
      expect(parts.text, 'What does this say?');
      expect(NovaMediaStore.hasPhotos(content), isTrue);
    });

    test('ordinary messages are untouched', () {
      final parts = NovaMediaStore.split('Hello [PHOTOS:x/y.jpg] there');
      expect(parts.photos, isEmpty);
      expect(parts.text, 'Hello [PHOTOS:x/y.jpg] there');
      expect(NovaMediaStore.join(const [], 'Hi'), 'Hi');
    });

    test('unsafe or invalid file references are ignored', () {
      final parts = NovaMediaStore.split('[PHOTOS:../etc/passwd,chat_1/../../x.jpg,/abs.jpg,chat_1/ok_0.jpg,a/b.exe]Hi');
      expect(parts.photos, ['chat_1/ok_0.jpg']);
      expect(NovaMediaStore.isValidRef('chat_1/m_0.jpg'), isTrue);
      expect(NovaMediaStore.isValidRef('chat_1/sub/m_0.jpg'), isFalse);
      expect(NovaMediaStore.join(['../x.jpg'], 'Hi'), 'Hi');
    });

    test('at most 3 photos per message', () {
      final refs = [for (var i = 0; i < 5; i++) 'c/m_$i.jpg'];
      expect(NovaMediaStore.split(NovaMediaStore.join(refs, '')).photos, hasLength(NovaMediaStore.maxPhotos));
    });

    test('what the text-only AI sees', () {
      expect(NovaMediaStore.forAi('[PHOTOS:c/m_0.jpg]Translate it'), '(I shared a photo.) Translate it');
      expect(NovaMediaStore.forAi('[PHOTOS:c/m_0.jpg,c/m_1.jpg]'), '(2 photos shared.)');
      expect(NovaMediaStore.forAi('Plain text'), 'Plain text');
    });

    test('chat names for photo messages', () {
      expect(NovaChatRepository.titleFrom('[PHOTOS:c/m_0.jpg]Read this receipt'), 'Read this receipt');
      expect(NovaChatRepository.titleFrom('[PHOTOS:c/m_0.jpg]'), 'Photo');
    });
  });

  test('image types the NOVA AI service accepts', () {
    expect(NovaMediaStore.mimeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
    expect(NovaMediaStore.mimeOf(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), 'image/png');
    expect(
        NovaMediaStore.mimeOf(Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])),
        'image/webp');
    expect(NovaMediaStore.mimeOf(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])), isNull); // GIF
    expect(NovaMediaStore.fileOf('../x.jpg'), isNull);
  });
}
