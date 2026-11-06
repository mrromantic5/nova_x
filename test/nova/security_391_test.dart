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
    // 3.12.3: both values are JSON literals on one line: var U = …, P = …, SUBMIT = …;
    final line = js.split('\n').firstWhere((l) => l.trim().startsWith('var U = '));
    final m = RegExp(r'^var U = (".*"), P = (".*"), SUBMIT = (true|false);$').firstMatch(line.trim());
    expect(m, isNotNull, reason: line);
    expect(m!.group(1), jsonEncode(user));
    expect(m.group(2), jsonEncode(pass));
    // Each literal decodes back unchanged, so nothing can break out into page script.
    expect(jsonDecode(m.group(1)!), user);
    expect(jsonDecode(m.group(2)!), pass);
    expect(m.group(3), 'false');
    expect(js.contains('</script>'), isTrue); // only inside the JSON string
  });

  test('version fallback matches pubspec.yaml', () {
    // Reads pubspec.yaml, so this never needs editing on a version bump.
    final m = RegExp(r'^version:\s*([\d.]+)\+(\d+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull, reason: 'pubspec.yaml has a version line');
    expect(AppInfo.fallbackVersion, m!.group(1));
    expect(AppInfo.fallbackBuild, int.parse(m.group(2)!));
  });
}
