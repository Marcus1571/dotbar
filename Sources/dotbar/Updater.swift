import Foundation
#if canImport(Sparkle)
import Sparkle

/// Sparkle wrapper, present only in packaged builds (`SPARKLE=1`): the dev build
/// compiles without the framework and everything below vanishes via `canImport`.
final class Updater: NSObject, SPUUpdaterDelegate {
    /// One controller for the app's lifetime; it drives the scheduled checks itself
    /// (startup + weekly, from the Info.plist SU keys).
    static let shared = Updater()

    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
#endif
