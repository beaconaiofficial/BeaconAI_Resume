// BottomBarIconButton (Template/Print/Export in ResumeEditorScreen and
// PreviewEditScreen's bottom bars, plus the Edit/Done Editing toggle in the
// latter): was two byte-identical private _BarButton classes (plus two
// duplicated inline Export-button blocks), both using a fixed
// Container(height: 48) wrapping an Icon+Text Column. At the app's 200%
// accessibility text-scale override, the scaled label no longer fit within
// 48px, producing a real, reproducible RenderFlex overflow — same bug class
// as the wizard nav bar fix. Consolidated into this one shared widget and
// fixed by swapping the fixed height for a BoxConstraints(minHeight: 48):
// keeps the 48dp minimum tap target at default scale, but lets the column
// grow past 48px instead of overflowing once text scales up.
//
// This test pumps BottomBarIconButton directly (both the outlined
// secondary style used for Template/Print/Edit, and the filled primary
// style used for Export) across the app's accessibility text-scale range,
// asserting no overflow exception fires, and separately confirms the
// 48x48dp minimum tap target still holds at default scale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/widgets/bottom_bar_icon_button.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required double width,
    required double textScale,
    required int buttonCount,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                // Same shape as the real bottom bars: N Expanded buttons in
                // a Row, secondary-styled buttons plus one primary Export.
                body: Row(
                  children: [
                    if (buttonCount >= 4)
                      Expanded(
                        child: BottomBarIconButton(
                          icon: Icons.edit_outlined,
                          label: 'Done Editing', // longest label in use
                          foregroundColor: Colors.blue,
                          borderColor: Colors.grey,
                          onTap: () {},
                        ),
                      ),
                    if (buttonCount >= 4) const SizedBox(width: 8),
                    Expanded(
                      child: BottomBarIconButton(
                        icon: Icons.style_outlined,
                        label: 'Template',
                        foregroundColor: Colors.blue,
                        borderColor: Colors.grey,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BottomBarIconButton(
                        icon: Icons.print_outlined,
                        label: 'Print',
                        foregroundColor: Colors.blue,
                        borderColor: Colors.grey,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BottomBarIconButton(
                        icon: Icons.ios_share_outlined,
                        label: 'Export',
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.blue,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
  }

  const widths = [320.0, 360.0, 411.0];
  const textScales = [1.0, 1.5, 2.0]; // 100%-200% per the in-app override

  for (final width in widths) {
    for (final textScale in textScales) {
      testWidgets(
          'no overflow at ${width}dp width, ${(textScale * 100).round()}% '
          'text scale — 3-button row (Template/Print/Export)', (tester) async {
        await pumpRow(tester, width: width, textScale: textScale, buttonCount: 3);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'no overflow at ${width}dp width, ${(textScale * 100).round()}% '
          'text scale — 4-button row (Edit/Template/Print/Export, PreviewEditScreen)',
          (tester) async {
        await pumpRow(tester, width: width, textScale: textScale, buttonCount: 4);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'meets the 48dp minimum tap target height at default text scale',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BottomBarIconButton(
              icon: Icons.style_outlined,
              label: 'Template',
              foregroundColor: Colors.blue,
              borderColor: Colors.grey,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final size = tester.getSize(find.byType(BottomBarIconButton));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets(
      'grows past 48dp rather than overflowing once text scale exceeds '
      'what fits in the default 48dp height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: const TextScaler.linear(2.0)),
              child: Scaffold(
                body: Center(
                  child: BottomBarIconButton(
                    icon: Icons.style_outlined,
                    label: 'Template',
                    foregroundColor: Colors.blue,
                    borderColor: Colors.grey,
                    onTap: () {},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(BottomBarIconButton));
    // Still respects the 48dp floor, and actually grew to fit the
    // 200%-scaled label rather than clipping/overflowing it.
    expect(size.height, greaterThan(48));
  });
}
