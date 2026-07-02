import 'dart:async';
import 'dart:developer' as dev;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provides real-time connectivity status app-wide.
/// Rule §10: Always check connectivity before any Claude API call.
/// The offline banner reads from this provider.
class ConnectivityNotifier extends AsyncNotifier<bool> {
  late StreamSubscription<ConnectivityResult> _subscription;

  @override
  Future<bool> build() async {
    final result = await Connectivity().checkConnectivity();
    final isOnline = _isOnline(result);
    dev.log('ConnectivityNotifier: initial check — result=$result isOnline=$isOnline',
        name: 'connectivity');

    _subscription = Connectivity().onConnectivityChanged.listen((result) {
      final online = _isOnline(result);
      dev.log('ConnectivityNotifier: changed — result=$result isOnline=$online',
          name: 'connectivity');
      state = AsyncValue.data(online);
    });

    ref.onDispose(() => _subscription.cancel());
    return isOnline;
  }

  static bool _isOnline(ConnectivityResult result) {
    if (kIsWeb) {
      // Browsers don't report a specific link type — connectivity_plus returns
      // ConnectivityResult.other when connected. Only .none means offline.
      return result != ConnectivityResult.none;
    }
    return result == ConnectivityResult.mobile ||
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.ethernet;
  }
}

final connectivityProvider = AsyncNotifierProvider<ConnectivityNotifier, bool>(
  ConnectivityNotifier.new,
);

/// Synchronous convenience — true when online, false when offline.
/// Defaults to true while the initial connectivity check is in flight so the
/// offline banner never flashes on launch before connectivity is confirmed.
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).valueOrNull ?? true;
});
