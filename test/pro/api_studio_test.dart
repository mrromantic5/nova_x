// test/pro/api_studio_test.dart (3.14.0) — API Studio request model.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/pro/api_studio.dart';

void main() {
  test('variables are substituted', () {
    final vars = ApiRequest.parseVars('baseUrl=https://api.example.com\ntoken=abc');
    expect(ApiRequest.substitute('{{baseUrl}}/items?t={{ token }}', vars), 'https://api.example.com/items?t=abc');
    expect(ApiRequest.substitute('{{missing}}', vars), '{{missing}}');
  });

  test('cURL import → export keeps method, URL and body', () {
    final r = ApiRequest.fromCurl("curl -X POST 'https://api.example.com/items' -H 'Content-Type: application/json' -d '{\"a\":1}'");
    expect(r, isNotNull);
    expect(r!.method, 'POST');
    expect(r.url, 'https://api.example.com/items');
    final out = r.toCurl(const {});
    expect(out, contains('-X POST'));
    expect(out, contains('https://api.example.com/items'));
    expect(out, contains('{"a":1}'));
  });

  test('not a cURL command', () {
    expect(ApiRequest.fromCurl('wget https://x'), isNull);
  });
}
