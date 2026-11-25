import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/screens/first_resume_setup_screen.dart';
import 'package:beaconai_resume/utils/preview_navigation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Black screen after first-run setup: privacy → onboarding → first-resume
// setup → wizard are all pushReplacementNamed, so the wizard is the only
// route. Finishing it replaced the wizard with the preview, and the editor's
// PopScope then popped the last route → black screen.
//
// The real FirstResumeSetupScreen drives both first-run paths (Build From
// Scratch, and Upload with a returned prefill map). The wizard and editor are
// stand-ins: the wizard's Finish calls the real openPreviewAfterWizard, and
// the editor stand-in copies ResumeEditorScreen's back handling exactly
// (PopScope(canPop: false) → save → Navigator.pop).
// ─────────────────────────────────────────────────────────────────────────────

const _dashboard = 'DASHBOARD';
const _preview = 'PREVIEW';

class _WizardStandIn extends StatelessWidget {
  const _WizardStandIn();
  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    return Scaffold(
      body: Column(children: [
        Text('WIZARD ${args?['path']}'),
        ElevatedButton(
          onPressed: () =>
              openPreviewAfterWizard(Navigator.of(context), 'resume-1'),
          child: const Text('Finish'),
        ),
      ]),
    );
  }
}

class _EditorStandIn extends StatelessWidget {
  const _EditorStandIn();
  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await Future<void>.value(); // stands in for _saveAllDirty()
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('editor-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        body: Text('$_preview ${args?['resumeId']}'),
      ),
    );
  }
}

Map<String, WidgetBuilder> _routes() => {
      AppConstants.routeDashboard: (_) =>
          const Scaffold(body: Text(_dashboard)),
      AppConstants.routeResumeBuilderWizard: (_) => const _WizardStandIn(),
      AppConstants.routePreviewEdit: (_) => const _EditorStandIn(),
      AppConstants.routeDocumentUpload: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, <String, dynamic>{
                'contact': {'fullName': 'Test User'},
              }),
              child: const Text('Apply All'),
            ),
          ),
    };

/// First-run state: FirstResumeSetupScreen is the root route, exactly as it
/// is after privacy → onboarding pushReplacementNamed into it.
Future<NavigatorState> _pumpFirstRun(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navKey,
    home: const FirstResumeSetupScreen(),
    routes: _routes(),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  return navKey.currentState!;
}

Future<void> _finishWizard(WidgetTester tester, String path) async {
  expect(find.text('WIZARD $path'), findsOneWidget);
  await tester.tap(find.text('Finish'));
  await tester.pumpAndSettle();
  expect(find.text('$_preview resume-1'), findsOneWidget);
}

Future<void> _expectBackLandsOnDashboard(
    WidgetTester tester, NavigatorState nav,
    {required bool systemBack}) async {
  if (systemBack) {
    // Android system back → Navigator.maybePop → PopScope.
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue, reason: 'back must not exit or blank the app');
  } else {
    await tester.tap(find.byKey(const Key('editor-back')));
  }
  await tester.pumpAndSettle();
  expect(find.text(_dashboard), findsOneWidget);
  expect(find.textContaining(_preview), findsNothing);
  expect(nav.canPop(), isFalse, reason: 'dashboard is the root route');
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final systemBack in [true, false]) {
    final how = systemBack ? 'system back' : 'app-bar back';

    testWidgets('Build From Scratch → Finish → $how lands on dashboard',
        (tester) async {
      final nav = await _pumpFirstRun(tester);
      await tester.tap(find.text('Build From Scratch'));
      await tester.pumpAndSettle();
      await _finishWizard(tester, 'scratch');
      await _expectBackLandsOnDashboard(tester, nav, systemBack: systemBack);
    });

    testWidgets('Upload → Apply All → Finish → $how lands on dashboard',
        (tester) async {
      final nav = await _pumpFirstRun(tester);
      await tester.tap(find.text('Upload Existing Resume'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply All'));
      await tester.pumpAndSettle();
      await _finishWizard(tester, 'upload');
      await _expectBackLandsOnDashboard(tester, nav, systemBack: systemBack);
    });
  }

  testWidgets('wizard opened from the dashboard still replaces itself',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text(_dashboard)),
      routes: _routes(),
    ));
    navKey.currentState!.pushNamed(AppConstants.routeResumeBuilderWizard,
        arguments: {'path': 'scratch'});
    await tester.pumpAndSettle();
    await _finishWizard(tester, 'scratch');

    // Stack is [dashboard, preview]: the wizard was replaced, not kept.
    await tester.tap(find.byKey(const Key('editor-back')));
    await tester.pumpAndSettle();
    expect(find.text(_dashboard), findsOneWidget);
    expect(find.textContaining('WIZARD'), findsNothing);
    expect(navKey.currentState!.canPop(), isFalse);
  });
}
