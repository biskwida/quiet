import Foundation

/// One Instagram login. `id` also names the account's private website storage on the phone.
public struct Account: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var label: String
}

public struct AccountList: Codable, Equatable, Sendable {
    public private(set) var accounts: [Account] = []
    public private(set) var selectedID: UUID?

    public init() {}

    public var selected: Account? {
        accounts.first { $0.id == selectedID }
    }

    /// Adds an account and selects it, so its login page is what shows next.
    @discardableResult
    public mutating func add(label: String) -> Account {
        let account = Account(id: UUID(), label: label)
        accounts.append(account)
        selectedID = account.id
        return account
    }

    public mutating func select(_ id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    public mutating func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = accounts.first?.id
        }
    }

    public mutating func rename(_ id: UUID, to label: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].label = label
    }
}

/// Saves the account list as a small JSON file.
public struct AccountFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// An absent file means a first launch. A file that exists but cannot be read is an error:
    /// treating it as empty would hide every account while their logins still sit on the phone.
    public func load() throws -> AccountList {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return AccountList() }
        return try JSONDecoder().decode(AccountList.self, from: Data(contentsOf: url))
    }

    public func save(_ list: AccountList) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(list).write(to: url, options: .atomic)
    }
}
