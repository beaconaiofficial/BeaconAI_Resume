import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// marketing/seed/marketing_main.dart pins the Pro tier and never starts
// AdMob/RevenueCat. It exists only for ad captures and must never ship.
void main() {
  const seedPath = 'marketing/seed/marketing_main.dart';

  test('the seed entrypoint lives outside lib/ and nothing in lib/ imports it',
      () {
    expect(seedPath.startsWith('lib/'), isFalse);
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final importsMarketing = RegExp(
              r'''^\s*(import|export|part)\s+['"][^'"]*marketing/''',
              multiLine: true)
          .hasMatch(f.readAsStringSync());
      expect(importsMarketing, isFalse,
          reason: '${f.path} must not import from the marketing folder');
    }
  });

  test('the seed entrypoint refuses to run as a release build', () {
    final seed = File(seedPath);
    if (!seed.existsSync()) return; // removed entirely: nothing to guard
    final src = seed.readAsStringSync();
    expect(src, contains('if (kReleaseMode)'));
    expect(src, contains('throw StateError'));
  });

  test('CI never builds a marketing entrypoint', () {
    final ci = File('codemagic.yaml');
    if (!ci.existsSync()) return;
    expect(ci.readAsStringSync().contains('marketing/'), isFalse);
  });

  test('marketing files are not bundled as Flutter assets', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('marketing/'), isFalse);
  });
}
