import Foundation
import Observation
import StasisCore
import os

/// Asks GitHub for the latest release at launch and once a day after that.
@MainActor
@Observable
final class UpdateChecker {
    static let releasePage = URL(string: "https://github.com/marstaj/Stasis/releases/latest")!
    private static let latestRelease = URL(string: "https://api.github.com/repos/marstaj/Stasis/releases/latest")!

    /// The newest release's version, set only while it is newer than the running app.
    private(set) var availableVersion: String?

    private let logger = Logger(subsystem: "dev.marstaj.Stasis", category: "updates")

    init() {
        guard let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let current = ReleaseVersion(string) else {
            // `swift run` has no bundle, so nothing to compare a release against.
            logger.info("No bundle version; update checks are off")
            return
        }
        Task { await check(against: current) }
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(against: current) }
        }
    }

    private func check(against current: ReleaseVersion) async {
        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            guard status == 200 else {
                logger.error("Update check failed: HTTP \(status ?? 0)")
                return
            }
            let tag = try JSONDecoder().decode(Release.self, from: data).tagName
            guard let latest = ReleaseVersion(tag) else {
                logger.error("Update check failed: release tag \(tag) is not a version")
                return
            }
            availableVersion = latest > current ? latest.description : nil
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
        }
    }

    private struct Release: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }
}
