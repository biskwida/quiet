import Foundation
import Testing
@testable import QuietCore

@Suite("Account list")
struct AccountListTests {
    @Test func startsEmptyWithNothingSelected() {
        let list = AccountList()
        #expect(list.accounts.isEmpty)
        #expect(list.selected == nil)
    }

    @Test func firstAccountAddedBecomesSelected() {
        var list = AccountList()
        let account = list.add(label: "Personal")
        #expect(account.label == "Personal")
        #expect(list.accounts == [account])
        #expect(list.selected == account)
    }

    @Test func newlyAddedAccountBecomesSelectedSoItsLoginShows() {
        var list = AccountList()
        list.add(label: "Personal")
        let second = list.add(label: "Work")
        #expect(list.accounts.count == 2)
        #expect(list.selected == second)
    }

    @Test func accountsGetDistinctStorageIdentifiers() {
        var list = AccountList()
        let first = list.add(label: "Personal")
        let second = list.add(label: "Personal")
        #expect(first.id != second.id)
    }

    @Test func selectingSwitchesAccount() {
        var list = AccountList()
        let first = list.add(label: "Personal")
        list.add(label: "Work")
        list.select(first.id)
        #expect(list.selected == first)
    }

    @Test func selectingAnUnknownAccountChangesNothing() {
        var list = AccountList()
        let first = list.add(label: "Personal")
        list.select(UUID())
        #expect(list.selected == first)
    }

    @Test func removingTheSelectedAccountFallsBackToTheFirstRemaining() {
        var list = AccountList()
        let first = list.add(label: "Personal")
        let second = list.add(label: "Work")
        list.remove(second.id)
        #expect(list.accounts == [first])
        #expect(list.selected == first)
    }

    @Test func removingAnotherAccountKeepsTheSelection() {
        var list = AccountList()
        let first = list.add(label: "Personal")
        let second = list.add(label: "Work")
        list.remove(first.id)
        #expect(list.accounts == [second])
        #expect(list.selected == second)
    }

    @Test func removingTheLastAccountLeavesNothingSelected() {
        var list = AccountList()
        let only = list.add(label: "Personal")
        list.remove(only.id)
        #expect(list.accounts.isEmpty)
        #expect(list.selected == nil)
    }

    @Test func renamingChangesOnlyTheLabel() {
        var list = AccountList()
        let account = list.add(label: "Personal")
        list.rename(account.id, to: "Main")
        #expect(list.accounts.map(\.label) == ["Main"])
        #expect(list.accounts.map(\.id) == [account.id])
    }
}

@Suite("Account file")
struct AccountFileTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "quiet-tests-\(UUID().uuidString)")
            .appending(path: "accounts.json")
    }

    @Test func loadingBeforeAnythingWasSavedGivesAnEmptyList() throws {
        let file = AccountFile(url: temporaryFile())
        #expect(try file.load() == AccountList())
    }

    @Test func savedListComesBackTheSame() throws {
        let file = AccountFile(url: temporaryFile())
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        var list = AccountList()
        let first = list.add(label: "Personal")
        list.add(label: "Work")
        list.select(first.id)

        try file.save(list)

        let loaded = try file.load()
        #expect(loaded == list)
        #expect(loaded.selected == first)
    }

    @Test func savedListIsFoundAgainInAFolderWhoseNameHasASpace() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "quiet tests \(UUID().uuidString)")
            .appending(path: "Application Support")
        let file = AccountFile(url: folder.appending(path: "accounts.json"))
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        var list = AccountList()
        list.add(label: "Personal")

        try file.save(list)

        #expect(try file.load() == list)
    }

    @Test func aDamagedFileIsReportedInsteadOfLookingEmpty() throws {
        let file = AccountFile(url: temporaryFile())
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.url)

        #expect(throws: (any Error).self) { try file.load() }
    }
}
