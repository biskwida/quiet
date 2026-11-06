import Foundation
import QuietCore
import SwiftUI
import WebKit

/// A link that leaves Instagram, shown in Safari's in-app viewer.
struct ExternalPage: Identifiable {
    let id = UUID()
    let url: URL
}

/// App-wide state: the accounts, the switches, and one live browser per account.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: AccountList
    @Published var feedEnabled: Bool { didSet { switchesChanged(Keys.feed, feedEnabled) } }
    @Published var storiesEnabled: Bool { didSet { switchesChanged(Keys.stories, storiesEnabled) } }
    @Published var lockEnabled: Bool { didSet { defaults.set(lockEnabled, forKey: Keys.lock) } }
    @Published var externalPage: ExternalPage?
    /// Set when something the user should know about went wrong (shown as an alert).
    @Published var problem: String?

    private enum Keys {
        static let feed = "feedEnabled"
        static let stories = "storiesEnabled"
        static let lock = "lockEnabled"
    }

    private let defaults = UserDefaults.standard
    private let file: AccountFile
    private var browsers: [UUID: AccountBrowser] = [:]

    init() {
        let folder = URL.applicationSupportDirectory.appending(path: "Quiet")
        let file = AccountFile(url: folder.appending(path: "accounts.json"))
        self.file = file
        // Both switches start off: a fresh install shows messages and nothing else.
        let saved = UserDefaults.standard
        feedEnabled = saved.bool(forKey: Keys.feed)
        storiesEnabled = saved.bool(forKey: Keys.stories)
        lockEnabled = saved.bool(forKey: Keys.lock)

        do {
            accounts = try file.load()
        } catch {
            // Keep the unreadable file instead of overwriting it, so nothing is lost.
            let aside = folder.appending(path: "accounts.damaged-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file.url, to: aside)
            accounts = AccountList()
            problem = "The saved account list could not be read and was set aside. "
                + "Add your accounts again; you will need to sign in to each."
        }
    }

    // MARK: - Browsers

    var selectedBrowser: AccountBrowser? {
        accounts.selected.map(browser(for:))
    }

    private func browser(for account: Account) -> AccountBrowser {
        if let existing = browsers[account.id] { return existing }
        let created = AccountBrowser(account: account, settings: guardSettings(for: account)) { [weak self] url in
            self?.externalPage = ExternalPage(url: url)
        }
        browsers[account.id] = created
        return created
    }

    private func guardSettings(for account: Account) -> GuardSettings {
        // The account's label is its Instagram username, which keeps its own stories reachable.
        GuardSettings(feedEnabled: feedEnabled, storiesEnabled: storiesEnabled, ownUsername: account.label)
    }

    private func switchesChanged(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
        for browser in browsers.values {
            browser.update(settings: guardSettings(for: browser.account))
        }
    }

    // MARK: - Accounts

    func addAccount(username: String) {
        let name = username.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !name.isEmpty else { return }
        accounts.add(label: name)
        save()
    }

    func select(_ id: UUID) {
        accounts.select(id)
        save()
    }

    /// Removes the account and erases its website storage, which signs it out.
    func remove(_ id: UUID) {
        browsers[id] = nil
        accounts.remove(id)
        save()
        Task {
            // The storage can only be erased once its web view has been released.
            try? await Task.sleep(for: .seconds(1))
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
            } catch {
                problem = "The account was removed from the list, but its saved login could not be erased: "
                    + error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            try file.save(accounts)
        } catch {
            problem = "The account list could not be saved: \(error.localizedDescription)"
        }
    }
}
