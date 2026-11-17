// test/devhub/devhub_tools_test.dart (3.14.0)
//
// Developer Hub Toolbox logic — the same pure Dart as NOVA X for Windows, so
// both versions give the same output for the same input.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/devhub/devhub_screen.dart';
import 'package:nova_x/features/devhub/devhub_tools.dart';

void main() {
  test('JSON format, minify and errors', () {
    final f = DevTools.jsonFormat('{"b":1,"a":[1,2]}', sortKeys: true);
    expect(f.ok, isTrue);
    expect(f.text.indexOf('"a"') < f.text.indexOf('"b"'), isTrue);
    expect(DevTools.jsonFormat('{"a":1}', minify: true).text, '{"a":1}');
    expect(DevTools.jsonFormat('{"a":').ok, isFalse);
  });

  test('hashes', () {
    final h = DevTools.hashes('abc').text;
    expect(h, contains('900150983cd24fb0d6963f7d28e17f72')); // MD5("abc")
    expect(h, contains('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')); // SHA-256("abc")
  });

  test('UUID v4 shape', () {
    final u = DevTools.uuidV4();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(u), isTrue);
    expect(DevTools.uuids(3).text.split('\n').length, 3);
  });

  test('number bases', () {
    final t = DevTools.numberBases('0xff').text;
    expect(t, contains('Decimal      255'));
    expect(t, contains('0b11111111'));
    expect(DevTools.numberBases('zz').ok, isFalse);
  });

  test('HTML entities round trip', () {
    const s = '<a href="?q=1&x=2">Tom\'s</a>';
    expect(DevTools.htmlDecode(DevTools.htmlEncode(s)), s);
  });

  test('case converter', () {
    final t = DevTools.caseConvert('user profile id').text;
    expect(t, contains('userProfileId'));
    expect(t, contains('USER_PROFILE_ID'));
    expect(t, contains('user-profile-id'));
  });

  test('Base64 round trip', () {
    final e = DevTools.base64Encode('NOVA X').text;
    expect(DevTools.base64Decode(e).text, contains('NOVA X'));
  });

  test('secrets use the requested length', () {
    expect(DevTools.secret(length: 40).length, 40);
  });

  test('Developer Hub address parsing (no port scanning)', () {
    expect(DevHubScreen.urlFromForTest('example.com'), 'https://example.com');
    expect(DevHubScreen.urlFromForTest('192.168.1.20:5173'), 'http://192.168.1.20:5173');
    expect(DevHubScreen.urlFromForTest('https://a.b/c'), 'https://a.b/c');
    expect(DevHubScreen.urlFromForTest('hello world'), isNull);
  });
}
