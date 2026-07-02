import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RevenueCatService
//
// Thin wrapper around purchases_flutter. All RevenueCat API surface the rest
// of the app touches goes through here — no other file should import
// purchases_flutter directly, so the SDK can be swapped or mocked in one place.
//
// Entitlement identifiers (configured in the RevenueCat dashboard, NOT
// product identifiers — confirmed against the live dashboard):
//   pro_access   → grants TierEnum.pro   (2 products: beaconai_pro_monthly,
//                                          beaconai_pro_annual)
//   basic_access → grants TierEnum.basic (2 products: beaconai_basic_monthly,
//                                          beaconai_basic_annual)
//   addon        → one-time $0.99 combo add-on (beaconai_addon_combo)
//   No active entitlement → TierEnum.free.
//
// The $0.99 cover letter add-on is tracked as the 'addon' entitlement in
// RevenueCat. Use hasAddonEntitlement() to check availability before gating
// addon features. See purchaseComboAddOn() for the purchase flow.
// ─────────────────────────────────────────────────────────────────────────────

class RevenueCatService {
  RevenueCatService._();

  static const String _proEntitlementId = 'pro_access';
  static const String _basicEntitlementId = 'basic_access';
  static const String _addonEntitlementId = 'addon';

  static const String _comboAddOnProductId = 'beaconai_addon_combo';

  static bool _configured = false;

  // ── Configuration ────────────────────────────────────────────────────────

  /// Configures the SDK with the platform-appropriate API key. Call once at
  /// app launch, before any other RevenueCatService method.
  static Future<void> configure() async {
    if (_configured) return;

    // kIsWeb MUST be checked before any Platform.* call — Platform.isAndroid/
    // isIOS throws UnsupportedError on web since dart:io Platform is unavailable
    // in a browser context.
    final PurchasesConfiguration configuration;
    if (kIsWeb) {
      configuration =
          PurchasesConfiguration(AppConstants.revenueCatApiKeyWeb);
    } else if (Platform.isAndroid) {
      configuration =
          PurchasesConfiguration(AppConstants.revenueCatApiKeyAndroid);
    } else if (Platform.isIOS || Platform.isMacOS) {
      configuration =
          PurchasesConfiguration(AppConstants.revenueCatApiKeyIos);
    } else {
      throw UnsupportedError('Unsupported platform for RevenueCat');
    }

    await Purchases.setLogLevel(LogLevel.warn);
    await Purchases.configure(configuration);
    _configured = true;
  }

  /// Registers a listener that fires whenever CustomerInfo changes —
  /// including changes that originate outside the app (renewal,
  /// cancellation, refund, family sharing changes, etc). The callback
  /// receives the already-mapped TierEnum so callers never touch the
  /// raw CustomerInfo.
  static void addTierChangeListener(void Function(TierEnum tier) onChange) {
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      onChange(_tierFromCustomerInfo(customerInfo));
    });
  }

  // ── Offerings ────────────────────────────────────────────────────────────

  /// Fetches the current default Offering's available packages. Returns an
  /// empty list (never throws for "no offering configured") so the Paywall
  /// can show a friendly empty state rather than crash — a missing/misnamed
  /// "current" offering in the dashboard is a configuration error, not
  /// something the user should see a stack trace for.
  static Future<List<Package>> getAvailablePackages() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? [];
    } on PlatformException {
      return [];
    }
  }

  /// Fetches the combo add-on's StoreProduct directly by product ID, since
  /// it's a one-time purchase rather than part of a subscription Offering.
  static Future<StoreProduct?> getComboAddOnProduct() async {
    try {
      final products = await Purchases.getProducts([_comboAddOnProductId]);
      return products.isNotEmpty ? products.first : null;
    } on PlatformException {
      return null;
    }
  }

  // ── Purchase ─────────────────────────────────────────────────────────────

  /// Purchases a subscription package. Returns the resulting TierEnum on
  /// success. Throws [RevenueCatPurchaseCancelledException] if the user
  /// backed out of the native purchase sheet (not a real error — the
  /// caller should treat this as a silent no-op, not show an error message).
  /// Throws [RevenueCatPurchaseException] for genuine failures.
  static Future<TierEnum> purchasePackage(Package package) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return _tierFromCustomerInfo(result.customerInfo);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        throw const RevenueCatPurchaseCancelledException();
      }
      throw RevenueCatPurchaseException(
          e.message ?? 'Purchase failed. Please try again.');
    }
  }

  /// Purchases the one-time $0.99 cover letter add-on. Does NOT touch tier —
  /// the caller is responsible for creating the local AddOnPurchase Hive
  /// record on success (Rule §2: this service never writes app data, only
  /// talks to RevenueCat).
  static Future<void> purchaseComboAddOn(StoreProduct product) async {
    try {
      await Purchases.purchase(PurchaseParams.storeProduct(product));
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        throw const RevenueCatPurchaseCancelledException();
      }
      throw RevenueCatPurchaseException(
          e.message ?? 'Purchase failed. Please try again.');
    }
  }

  // ── Restore ──────────────────────────────────────────────────────────────

  /// Restores prior purchases for the current store account. Returns the
  /// resulting TierEnum. Does not throw on "nothing to restore" — that's a
  /// valid outcome (tier stays/returns to free), only genuine API/network
  /// failures throw.
  static Future<TierEnum> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      return _tierFromCustomerInfo(customerInfo);
    } on PlatformException catch (e) {
      throw RevenueCatPurchaseException(
          e.message ?? 'Restore failed. Please try again.');
    }
  }

  // ── Current state ────────────────────────────────────────────────────────

  /// Reads the current tier without making a purchase — used at app launch
  /// to sync UserSettings.tier with whatever RevenueCat actually has on
  /// file, since Rule §7 says tier is sourced from RevenueCat at runtime,
  /// never trusted from local storage alone.
  static Future<TierEnum> getCurrentTier() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return _tierFromCustomerInfo(customerInfo);
    } on PlatformException {
      // If RevenueCat is unreachable, fail closed to free rather than
      // silently trusting a possibly-stale local tier value.
      return TierEnum.free;
    }
  }

  /// Returns true if the user has an active 'addon' entitlement in RevenueCat,
  /// meaning an unconsumed $0.99 combo add-on purchase is available to use.
  /// Fails closed to false if RevenueCat is unreachable.
  static Future<bool> hasAddonEntitlement() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return customerInfo.entitlements.active.containsKey(_addonEntitlementId);
    } on PlatformException {
      return false;
    }
  }

  // ── Mapping ──────────────────────────────────────────────────────────────

  static TierEnum _tierFromCustomerInfo(CustomerInfo customerInfo) {
    final active = customerInfo.entitlements.active;
    if (active.containsKey(_proEntitlementId)) return TierEnum.pro;
    if (active.containsKey(_basicEntitlementId)) return TierEnum.basic;
    return TierEnum.free;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exceptions
// ─────────────────────────────────────────────────────────────────────────────

class RevenueCatConfigException implements Exception {
  const RevenueCatConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RevenueCatPurchaseException implements Exception {
  const RevenueCatPurchaseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when the user dismisses the native purchase sheet without buying.
/// Distinct from RevenueCatPurchaseException so callers can silently ignore
/// it rather than show an error — cancelling is not a failure state.
class RevenueCatPurchaseCancelledException implements Exception {
  const RevenueCatPurchaseCancelledException();
}
