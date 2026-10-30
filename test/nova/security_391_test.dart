// 3.9.1: saved passwords are written into pages as JSON strings, so no
// character in a password can end the string and run as page script.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/core/services/app_info.dart';
import 'package:nova_x/core/services/password_service.dart';

void main() {
  test('autofill JS escapes quotes, backslashes, line breaks and </script>', () {
    const user = "a'b\"c";
    const pass = "p\\';alert(1);//\n</script>`\${x}";
    final js = PasswordService.autofillJS(user, pass);
    expect(js, contains('inp.value = ${jsonEncode(user)};'));
    expect(js, contains('inp.value = ${jsonEncode(pass)};'));
    // The value line is one valid JSON string that decodes back unchanged.
    final line = js.split('\n').firstWhere((l) => l.contains('inp.value = "p'));
    final literal = line.trim().substring('inp.value = '.length, line.trim().length - 1);
    expect(jsonDecode(literal), pass);
  });

  test('version fallback matches pubspec.yaml', () {
    // Reads pubspec.yaml, so this never needs editing on a version bump.
    final m = RegExp(r'^version:\s*([\d.]+)\+(\d+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull, reason: 'pubspec.yaml has a version line');
    expect(AppInfo.fallbackVersion, m!.group(1));
    expect(AppInfo.fallbackBuild, int.parse(m.group(2)!));
  });
}
