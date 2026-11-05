import 'package:droidlab_application/src/pages/debloat_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldSkipDebloatAction', () {
    test('skips disable, enable, and uninstall for packages not installed for this user', () {
      for (final action in ['disable', 'enable', 'uninstall']) {
        expect(
          shouldSkipDebloatAction(
            action: action,
            installed: false,
            disabled: false,
          ),
          isTrue,
          reason: action,
        );
      }
      expect(
        shouldSkipDebloatAction(action: 'restore', installed: false, disabled: false),
        isFalse,
      );
    });

    test('skips disable when already disabled and enable when already enabled', () {
      expect(
        shouldSkipDebloatAction(action: 'disable', installed: true, disabled: true),
        isTrue,
      );
      expect(
        shouldSkipDebloatAction(action: 'enable', installed: true, disabled: false),
        isTrue,
      );
    });

    test('allows applicable state changes and restore after uninstall', () {
      expect(
        shouldSkipDebloatAction(action: 'disable', installed: true, disabled: false),
        isFalse,
      );
      expect(
        shouldSkipDebloatAction(action: 'enable', installed: true, disabled: true),
        isFalse,
      );
      expect(
        shouldSkipDebloatAction(action: 'uninstall', installed: true, disabled: false),
        isFalse,
      );
      expect(
        shouldSkipDebloatAction(action: 'restore', installed: true, disabled: false),
        isTrue,
      );
    });
  });
}
