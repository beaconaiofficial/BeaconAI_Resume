import Flutter
import UIKit
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// Thin bridge to Apple's Declared Age Range framework.
///
/// Contract mirrors AgeSignalsChannel.kt: method "fetch" ALWAYS replies with a
/// map (never a FlutterError) so Dart parses exactly one shape:
///   status   : "shared" | "notShared" | "notApplicable" | "unavailable" | "error"
///   ageLower : Int?   (inclusive; a nil lowerBound from Apple means "below the
///                      first gate", so it is sent as 0 — see below)
///   ageUpper : Int?   (inclusive; nil for the top band)
///   errorCode: String? (diagnostic only)
///
/// Flow (approved in Stage 0):
///   - iOS < 26.2 → "notApplicable" without calling anything.
///     TODO(age-assurance): revisit iOS 26.0–26.1 before 2027-01-01 if Apple's
///     guidance changes — today we can't check eligibility there, so we skip.
///   - iOS 26.2+ → isEligibleForAgeFeatures; false → "notApplicable", no sheet.
///   - eligible → requestAgeRange(ageGates: 13, 16, 18) which may present a
///     system sheet. The system caches answers and may override our gates with
///     regulatory ones, so Dart classifies from the returned bounds.
///
/// Logging is DEBUG-only and tagged [AGE SIGNAL]. No age values are persisted
/// natively.
final class AgeSignalsChannel: NSObject, FlutterPlugin {
  static let channelName = "dev.getbeaconai/age_signals"

  // Non-UI steps fail fast; the request step may show a sheet the person
  // reads and answers, so it gets a long ceiling.
  private static let quickTimeoutSeconds: Double = 15
  private static let promptTimeoutSeconds: Double = 180

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AgeSignalsChannel(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "fetch" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let reply = OnceReply(result)
    #if canImport(DeclaredAgeRange)
      if #available(iOS 26.2, *) {
        Task { @MainActor in await Self.fetch(reply) }
        return
      }
    #endif
    Self.debugLog("iOS < 26.2 (or SDK without DeclaredAgeRange); skipping")
    reply.send(["status": "notApplicable", "errorCode": "OS_UNSUPPORTED"])
  }

  #if canImport(DeclaredAgeRange)
    @available(iOS 26.2, *)
    @MainActor
    private static func fetch(_ reply: OnceReply) async {
      // 1. Eligibility (reported to hang on some builds → timeout).
      let eligible: Bool
      do {
        eligible = try await withTimeout(quickTimeoutSeconds, step: "eligibility") {
          try await AgeRangeService.shared.isEligibleForAgeFeatures
        }
      } catch {
        reply.send(failure(error, step: "eligibility"))
        return
      }
      guard eligible else {
        debugLog("not eligible for age features; no sheet shown")
        reply.send(["status": "notApplicable"])
        return
      }

      // 2. Request — needs a view controller to anchor the system sheet.
      guard let presenter = topViewController() else {
        reply.send(["status": "unavailable", "errorCode": "NO_VIEW_CONTROLLER"])
        return
      }
      do {
        let response = try await withTimeout(promptTimeoutSeconds, step: "request") {
          try await AgeRangeService.shared.requestAgeRange(
            ageGates: 13, 16, 18, in: presenter)
        }
        switch response {
        case .declinedSharing:
          reply.send(["status": "notShared"])
        case .sharing(let range):
          // Apple: nil lowerBound == below the first gate. Send 0 so Dart's
          // "both bounds null == no data" rule stays platform-neutral.
          let lower: Int = range.lowerBound ?? 0
          var payload: [String: Any] = ["status": "shared", "ageLower": lower]
          if let upper = range.upperBound { payload["ageUpper"] = upper }
          reply.send(payload)
        @unknown default:
          reply.send(["status": "unavailable", "errorCode": "UNKNOWN_RESPONSE"])
        }
      } catch {
        reply.send(failure(error, step: "request"))
      }
    }

    @available(iOS 26.2, *)
    private static func failure(_ error: Error, step: String) -> [String: Any] {
      let code: String
      if let ageError = error as? AgeRangeService.Error {
        // Only the iOS 26.0 cases. declinedOnboarding, invalidAccount and
        // network are iOS 27.0 SDK additions and don't compile on Xcode 26;
        // they (and any later case) land in the default branch as "error",
        // which Dart treats like every other failure: keep the last stored
        // bracket, never crash.
        switch ageError {
        case .notAvailable:
          debugLog("unavailable in step=\(step) code=NOT_AVAILABLE")
          return ["status": "unavailable", "errorCode": "NOT_AVAILABLE"]
        case .invalidRequest:
          code = "INVALID_REQUEST"
        default:
          code = "AGE_RANGE_\(String(describing: ageError))"
        }
      } else if error is AgeSignalTimeout {
        code = "TIMEOUT_\(step)"
      } else {
        code = String(describing: type(of: error))
      }
      debugLog("failure in step=\(step) code=\(code)")
      return ["status": "error", "errorCode": code]
    }
  #endif

  // ── Helpers ────────────────────────────────────────────────────────────────

  @MainActor
  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window =
      scenes.filter { $0.activationState == .foregroundActive }
      .flatMap { $0.windows }.first { $0.isKeyWindow }
      ?? scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private static func debugLog(_ message: String) {
    #if DEBUG
      print("[AGE SIGNAL] \(message)")
    #endif
  }
}

struct AgeSignalTimeout: Error {}

/// Races `operation` against a timeout. The loser is cancelled; if the
/// underlying API ignores cancellation its late result is simply discarded.
@MainActor
private func withTimeout<T: Sendable>(
  _ seconds: Double, step: String,
  _ operation: @escaping @MainActor @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { @MainActor in try await operation() }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw AgeSignalTimeout()
    }
    defer { group.cancelAll() }
    guard let first = try await group.next() else { throw AgeSignalTimeout() }
    return first
  }
}

/// Guarantees FlutterResult is invoked exactly once, on the main thread.
private final class OnceReply: @unchecked Sendable {
  private let result: FlutterResult
  private var sent = false
  private let lock = NSLock()

  init(_ result: @escaping FlutterResult) { self.result = result }

  func send(_ payload: [String: Any]) {
    lock.lock()
    if sent {
      lock.unlock()
      return
    }
    sent = true
    lock.unlock()
    if Thread.isMainThread {
      result(payload)
    } else {
      DispatchQueue.main.async { self.result(payload) }
    }
  }
}
