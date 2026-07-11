// Guards against kComboTestMode being accidentally left/flipped to true in a
// production build, which would silently grant the $0.99 combo add-on
// without a real purchase.
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/constants/app_constants.dart';

void main() {
  test('kComboTestMode must be false for production release', () {
    expect(AppConstants.kComboTestMode, isFalse,
        reason:
            'kComboTestMode bypasses the real IAP purchase for the combo '
            'add-on. It must be false before shipping to Google Play.');
  });
}
