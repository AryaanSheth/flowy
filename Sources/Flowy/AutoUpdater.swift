import AppKit
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AutoUpdater: NSObject {
#if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
#endif

    var isAvailable: Bool {
#if canImport(Sparkle)
        updaterController != nil
#else
        false
#endif
    }

    override init() {
        super.init()

#if canImport(Sparkle)
        guard Self.hasSparkleConfiguration else {
            FlowyLog.warn("Sparkle framework is bundled but update feed/signing configuration is missing")
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        FlowyLog.info("Sparkle auto-update initialized")
#else
        FlowyLog.info("Sparkle auto-update unavailable in this build")
#endif
    }

    func checkForUpdates(_ sender: Any?) {
#if canImport(Sparkle)
        updaterController?.checkForUpdates(sender)
#endif
    }

#if canImport(Sparkle)
    private static var hasSparkleConfiguration: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feedURL = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !feedURL.isEmpty && !publicKey.isEmpty
    }
#endif
}
