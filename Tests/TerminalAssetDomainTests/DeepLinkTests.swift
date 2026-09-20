import Foundation
import Testing
@testable import TerminalAssetDomain

@Suite("DeepLink")
struct DeepLinkTests {
    @Test(arguments: [
        "ext:abc123|1800000000",
        "fp:cal-1|team standup|1800000000",
        "ext:กาแฟ ประชุม|1800000000",
        "ext:a&b=c?d#e|1"
    ])
    func anEventLinkRoundTrips(_ raw: String) throws {
        let link = DeepLink.event(EventKey(rawValue: raw))
        let url = try #require(link.url)
        #expect(DeepLink(url: url) == link)
    }

    @Test func theURLUsesTheAppScheme() throws {
        let url = try #require(DeepLink.event(EventKey(rawValue: "ext:a|1")).url)
        #expect(url.scheme == "terminalasset")
        #expect(url.host == "event")
    }

    @Test func linksFromOtherSchemesAreIgnored() throws {
        let url = try #require(URL(string: "https://example.com/event?key=ext:a|1"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test func unknownDestinationsAreIgnored() throws {
        let url = try #require(URL(string: "terminalasset://delete?key=ext:a|1"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test func aMissingOrEmptyKeyIsIgnored() throws {
        #expect(DeepLink(url: try #require(URL(string: "terminalasset://event"))) == nil)
        #expect(DeepLink(url: try #require(URL(string: "terminalasset://event?key="))) == nil)
    }

    @Test func theSchemeIsCaseInsensitive() throws {
        let url = try #require(URL(string: "TerminalAsset://Event?key=ext%3Aa%7C1"))
        #expect(DeepLink(url: url) == .event(EventKey(rawValue: "ext:a|1")))
    }
}
