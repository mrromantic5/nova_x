// test/nova/nova_wake_test.dart
//
// "Hey NOVA" status from Android, including "Listen when the screen is off"
// (off by default) and the battery setting it relies on.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/services/nova_wake.dart';

void main() {
  test('screen-off listening is off unless Android reports it on', () {
    const empty = NovaWakeStatus();
    expect(empty.screenOff, isFalse);
    expect(empty.batteryUnrestricted, isFalse);

    final old = NovaWakeStatus.fromMap({'supported': true, 'enabled': true, 'running': true});
    expect(old.enabled, isTrue);
    expect(old.screenOff, isFalse); // older native code without the option

    final on = NovaWakeStatus.fromMap({
      'supported': true,
      'enabled': true,
      'running': true,
      'background': true,
      'overlay': true,
      'screenOff': true,
      'batteryUnrestricted': true,
      'error': null,
    });
    expect(on.screenOff, isTrue);
    expect(on.batteryUnrestricted, isTrue);
    expect(on.overlay, isTrue);
    expect(on.error, isNull);
  });
}
