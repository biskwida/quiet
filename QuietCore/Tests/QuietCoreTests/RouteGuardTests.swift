import Foundation
import Testing
@testable import QuietCore

private func ig(_ path: String) -> URL {
    URL(string: "https://www.instagram.com" + path)!
}

private let inbox = Decision.sendTo("/direct/inbox/")

@Suite("Fixed route rules")
struct FixedRouteTests {
    @Test(arguments: ["/direct/inbox/", "/direct/t/1234567890/", "/direct/requests/", "/direct/new/"])
    func messagesAreAlwaysAllowed(path: String) {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig(path)) == .allow)
    }

    @Test(arguments: ["/reels/", "/reels", "/someuser/reels/", "/reels/audio/12345/"])
    func reelsSectionIsNeverAllowed(path: String) {
        var routeGuard = RouteGuard(settings: GuardSettings(feedEnabled: true, storiesEnabled: true))
        #expect(routeGuard.decide(url: ig(path)) == inbox)
    }

    @Test(arguments: ["/reel/Cabc123_-x/", "/reels/Cabc123_-x/", "/someuser/reel/Cabc123_-x/"])
    func reelNotOpenedFromAChatIsRefused(path: String) {
        var routeGuard = RouteGuard(settings: GuardSettings(feedEnabled: true, storiesEnabled: true))
        #expect(routeGuard.decide(url: ig(path), from: ig("/")) == inbox)
        #expect(routeGuard.decide(url: ig(path), from: nil) == inbox)
    }

    @Test(arguments: ["/explore/tags/sunset/", "/explore/locations/123/", "/explore/search/keyword/"])
    func exploreListingsAreRefused(path: String) {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig(path)) == inbox)
    }

    // Seen on the live site: the Search button in the bottom bar points at "/explore/".
    // The grid of suggested posts on that page is removed by the hiding rules instead.
    @Test(arguments: ["/explore/", "/explore/search/"])
    func searchIsAllowed(path: String) {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig(path)) == .allow)
    }

    @Test func feedIsRefusedWhileItsSwitchIsOff() {
        var routeGuard = RouteGuard(settings: GuardSettings(feedEnabled: false))
        #expect(routeGuard.decide(url: ig("/")) == inbox)
        #expect(routeGuard.decide(url: URL(string: "https://www.instagram.com")!) == inbox)
    }

    @Test func feedIsAllowedWhileItsSwitchIsOn() {
        var routeGuard = RouteGuard(settings: GuardSettings(feedEnabled: true))
        #expect(routeGuard.decide(url: ig("/")) == .allow)
        #expect(routeGuard.decide(url: ig("/?variant=following")) == .allow)
    }

    @Test(arguments: ["/stories/someuser/3141592653/", "/stories/someuser/", "/stories/highlights/17900000000/"])
    func otherPeoplesStoriesFollowTheStoriesSwitch(path: String) {
        var off = RouteGuard(settings: GuardSettings(storiesEnabled: false, ownUsername: "me"))
        #expect(off.decide(url: ig(path), from: ig("/someuser/")) == inbox)

        var on = RouteGuard(settings: GuardSettings(storiesEnabled: true, ownUsername: "me"))
        #expect(on.decide(url: ig(path), from: ig("/someuser/")) == .allow)
    }

    @Test func ownStoriesAreAllowedWhileStoriesAreOff() {
        var routeGuard = RouteGuard(settings: GuardSettings(storiesEnabled: false, ownUsername: "Tanya.T"))
        #expect(routeGuard.decide(url: ig("/stories/tanya.t/3141592653/")) == .allow)
    }

    @Test(arguments: ["/p/Cabc123/", "/someuser/p/Cabc123/", "/someuser/", "/someuser/tagged/", "/notifications/", "/accounts/edit/"])
    func ordinaryPagesAreAllowed(path: String) {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig(path)) == .allow)
    }

    @Test(arguments: ["/accounts/login/", "/accounts/login/two_factor", "/challenge/abc/def/", "/accounts/onetap/"])
    func loginAndSecurityPagesAreAllowed(path: String) {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig(path)) == .allow)
        #expect(RouteGuard.isAuthPage(ig(path)))
    }

    @Test(arguments: ["/direct/inbox/", "/someuser/", "/", "/accounts/edit/"])
    func ordinaryPagesAreNotLoginPages(path: String) {
        #expect(!RouteGuard.isAuthPage(ig(path)))
    }

    @Test(arguments: [
        "https://example.com/page",
        "https://instagram.com.evil.example/direct/inbox/",
        "https://notinstagram.com/direct/inbox/",
        "http://www.instagram.com/direct/inbox/",
        "https://l.facebook.com/l.php?u=x",
    ])
    func anythingThatIsNotInstagramOverHTTPSOpensOutside(address: String) {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: URL(string: address)!) == .openOutside)
    }

    @Test(arguments: ["https://instagram.com/direct/inbox/", "https://WWW.Instagram.com/direct/inbox/"])
    func instagramHostsAreRecognised(address: String) {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: URL(string: address)!) == .allow)
    }
}

@Suite("One shared item from a chat")
struct SharedItemTests {
    private let thread = ig("/direct/t/1234567890/")
    private let threadPath = Decision.sendTo("/direct/t/1234567890/")

    @Test func reelOpenedFromAChatIsAllowed() {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig("/reel/AAA111/"), from: thread) == .allow)
    }

    @Test func sameReelUnderItsOtherAddressStaysAllowed() {
        var routeGuard = RouteGuard()
        _ = routeGuard.decide(url: ig("/reel/AAA111/"), from: thread)
        #expect(routeGuard.decide(url: ig("/reels/AAA111/"), from: ig("/reel/AAA111/")) == .allow)
    }

    // Seen on the live site: profile grids link reels as "/<user>/reel/<code>/".
    @Test func reelUnderAProfileAddressCountsAsTheSameReel() {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig("/someuser/reel/AAA111/"), from: thread) == .allow)
        #expect(routeGuard.decide(url: ig("/reel/AAA111/"), from: ig("/someuser/reel/AAA111/")) == .allow)
    }

    // Seen on the live site: a shared post opens as "/p/<code>/" over the chat, and a reel
    // tile that links to "/reel/<code>/" lands on "/p/<code>/" as well.
    @Test func postOpenedFromAChatIsTheOneSharedItem() {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig("/p/AAA111/"), from: thread) == .allow)
        #expect(routeGuard.decide(url: ig("/p/BBB222/"), from: ig("/p/AAA111/")) == threadPath)
    }

    @Test func reelThatLandsOnAPostAddressIsStillTheSameItem() {
        var routeGuard = RouteGuard()
        _ = routeGuard.decide(url: ig("/reel/AAA111/"), from: thread)
        #expect(routeGuard.decide(url: ig("/p/AAA111/"), from: ig("/reel/AAA111/")) == .allow)
    }

    @Test func movingToAnotherReelReturnsToTheChat() {
        var routeGuard = RouteGuard()
        _ = routeGuard.decide(url: ig("/reel/AAA111/"), from: thread)
        #expect(routeGuard.decide(url: ig("/reels/BBB222/"), from: ig("/reel/AAA111/")) == threadPath)
    }

    @Test func reelsSectionFromASharedReelReturnsToTheChat() {
        var routeGuard = RouteGuard()
        _ = routeGuard.decide(url: ig("/reel/AAA111/"), from: thread)
        #expect(routeGuard.decide(url: ig("/reels/"), from: ig("/reel/AAA111/")) == threadPath)
    }

    @Test func sharedReelIsNoLongerAllowedOnceYouLeaveIt() {
        var routeGuard = RouteGuard()
        _ = routeGuard.decide(url: ig("/reel/AAA111/"), from: thread)
        _ = routeGuard.decide(url: ig("/someuser/"), from: ig("/reel/AAA111/"))
        #expect(routeGuard.decide(url: ig("/reel/AAA111/"), from: ig("/someuser/")) == .sendTo("/direct/inbox/"))
    }

    @Test func storyOpenedFromAChatIsAllowedWhileStoriesAreOff() {
        var routeGuard = RouteGuard(settings: GuardSettings(storiesEnabled: false))
        #expect(routeGuard.decide(url: ig("/stories/someuser/111/"), from: thread) == .allow)
    }

    @Test func nextStoryOfTheSamePersonReturnsToTheChat() {
        var routeGuard = RouteGuard(settings: GuardSettings(storiesEnabled: false))
        _ = routeGuard.decide(url: ig("/stories/someuser/111/"), from: thread)
        #expect(routeGuard.decide(url: ig("/stories/someuser/222/"), from: ig("/stories/someuser/111/")) == threadPath)
    }

    @Test func storyOfAnotherPersonReturnsToTheChat() {
        var routeGuard = RouteGuard(settings: GuardSettings(storiesEnabled: false))
        _ = routeGuard.decide(url: ig("/stories/someuser/111/"), from: thread)
        #expect(routeGuard.decide(url: ig("/stories/otheruser/333/"), from: ig("/stories/someuser/111/")) == threadPath)
    }

    @Test func sharedStoryStaysSingleEvenWhileStoriesAreOn() {
        var routeGuard = RouteGuard(settings: GuardSettings(storiesEnabled: true))
        _ = routeGuard.decide(url: ig("/stories/someuser/111/"), from: thread)
        #expect(routeGuard.decide(url: ig("/stories/someuser/222/"), from: ig("/stories/someuser/111/")) == threadPath)
    }

    @Test func goingBackToTheChatFromASharedItemIsAllowed() {
        var routeGuard = RouteGuard()
        _ = routeGuard.decide(url: ig("/reel/AAA111/"), from: thread)
        #expect(routeGuard.decide(url: thread, from: ig("/reel/AAA111/")) == .allow)
    }

    @Test func aReelFromTheInboxListIsNotASharedItem() {
        var routeGuard = RouteGuard()
        #expect(routeGuard.decide(url: ig("/reel/AAA111/"), from: ig("/direct/inbox/")) == .sendTo("/direct/inbox/"))
    }
}

@Suite("Where video may play")
struct VideoTests {
    private let thread = ig("/direct/t/1234567890/")

    @Test(arguments: ["/direct/inbox/", "/direct/t/1234567890/"])
    func videoPlaysInChats(path: String) {
        let routeGuard = RouteGuard()
        #expect(routeGuard.allowsVideo(at: ig(path)))
    }

    @Test func videoPlaysInTheStoryViewer() {
        let routeGuard = RouteGuard()
        #expect(routeGuard.allowsVideo(at: ig("/stories/someuser/111/")))
    }

    @Test(arguments: ["/", "/someuser/", "/p/AAA111/", "/someuser/p/AAA111/", "/explore/", "/notifications/"])
    func videoDoesNotPlayOnOrdinaryPages(path: String) {
        let routeGuard = RouteGuard(settings: GuardSettings(feedEnabled: true, storiesEnabled: true))
        #expect(!routeGuard.allowsVideo(at: ig(path)))
    }

    @Test func videoPlaysOnTheItemOpenedFromAChatAndOnlyThere() {
        var routeGuard = RouteGuard()
        _ = routeGuard.decide(url: ig("/p/AAA111/"), from: thread)
        #expect(routeGuard.allowsVideo(at: ig("/p/AAA111/")))
        #expect(routeGuard.allowsVideo(at: ig("/reel/AAA111/")))
        #expect(!routeGuard.allowsVideo(at: ig("/p/BBB222/")))
    }

    @Test func videoStopsOnceTheSharedItemIsLeft() {
        var routeGuard = RouteGuard()
        _ = routeGuard.decide(url: ig("/p/AAA111/"), from: thread)
        _ = routeGuard.decide(url: ig("/someuser/"), from: ig("/p/AAA111/"))
        #expect(!routeGuard.allowsVideo(at: ig("/p/AAA111/")))
    }

    @Test func videoDoesNotPlayOutsideInstagram() {
        let routeGuard = RouteGuard()
        #expect(!routeGuard.allowsVideo(at: URL(string: "https://example.com/direct/inbox/")!))
    }
}
