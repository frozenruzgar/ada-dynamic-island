import AdaCore
import AppKit
import SwiftUI

enum AdaReleaseCheck {
    private struct Release: Decodable {
        let tag_name: String
    }

    static let releasesURL = URL(string: "https://github.com/frozenruzgar/ada-dynamic-island/releases")!
    private static let endpoint = URL(string: "https://api.github.com/repos/frozenruzgar/ada-dynamic-island/releases?per_page=1")!

    static func latestVersion(from data: Data) throws -> String? {
        guard let tag = try JSONDecoder().decode([Release].self, from: data).first?.tag_name,
              tag.first == "v" else { return nil }
        let version = String(tag.dropFirst())
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } && Int(part) != nil
        }) else { return nil }
        return version
    }

    static func availableVersion(current: String, response: Data) throws -> String? {
        guard let latest = try latestVersion(from: response),
              ApplicationVersion(current, build: "0") < ApplicationVersion(latest, build: "0") else { return nil }
        return latest
    }

    static func fetch() async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

struct UpdateCheckView: View {
    @AppStorage("ada.updateCheckEnabled") private var allowed = false
    @State private var check: Task<Void, Never>?
    @State private var message: String?
    @State private var available: String?

    var body: some View {
        Section(L10n.string("Güncellemeler")) {
            Toggle(L10n.string("GitHub sürüm kontrolüne izin ver"), isOn: $allowed)
            Text(L10n.string("Kontrol düğmesi GitHub’dan yayın sürümünü okur. Kurulum sana kalır."))
                .adaFont(size: Typography.caption).foregroundStyle(.secondary)
            Button(L10n.string("Güncellemeyi kontrol et"), action: start)
                .disabled(!allowed || check != nil)
            if check != nil { ProgressView().controlSize(.small) }
            if let message { Text(message).adaFont(size: Typography.caption) }
            if let available {
                Link(L10n.string("Ada \(available) yayınlarına git"),
                     destination: AdaReleaseCheck.releasesURL)
            }
        }
        .onChange(of: allowed) { _, value in
            if !value { cancel() }
        }
        .onDisappear(perform: cancel)
    }

    private func cancel() {
        check?.cancel()
        check = nil
        message = nil
        available = nil
    }

    private func start() {
        guard allowed, check == nil else { return }
        message = nil
        available = nil
        check = Task {
            do {
                let response = try await AdaReleaseCheck.fetch()
                guard !Task.isCancelled else { return }
                if try AdaReleaseCheck.latestVersion(from: response) == nil {
                    message = L10n.string("GitHub’da okunabilir bir yayın bulunamadı.")
                } else {
                    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                    available = try AdaReleaseCheck.availableVersion(current: current, response: response)
                    if available == nil { message = L10n.string("Ada güncel.") }
                }
            } catch {
                guard !Task.isCancelled else { return }
                message = L10n.string("Sürüm kontrolü başarısız oldu. Tekrar deneyebilirsin.")
            }
            check = nil
        }
    }
}
