// Conditional export — on web the dart:html implementation is used;
// on native the stub is used (never called due to kIsWeb guard at call sites).
export 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart';
