import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';

/// Opens the resume editor/preview once the wizard finishes.
///
/// During first-run setup every screen before the wizard (privacy policy,
/// onboarding, first-resume setup) is replaced rather than pushed, so the
/// wizard is the only route. Replacing it with the preview left the preview
/// as the only route, and its back handler popped it into a black screen.
///
/// When the wizard is the root route, the stack is rebuilt as
/// [dashboard, preview] so Back lands on the dashboard. Otherwise (wizard
/// pushed from the dashboard or the editor) the wizard is replaced as before.
void openPreviewAfterWizard(NavigatorState navigator, String? resumeId) {
  final args = {'resumeId': resumeId};
  if (navigator.canPop()) {
    navigator.pushReplacementNamed(AppConstants.routePreviewEdit,
        arguments: args);
    return;
  }
  navigator.pushNamedAndRemoveUntil(AppConstants.routeDashboard, (_) => false);
  navigator.pushNamed(AppConstants.routePreviewEdit, arguments: args);
}
