import Foundation
import Testing
@testable import MNotchCore

struct UpdaterTests {
    private func release(tag: String, assets: [String] = [Updater.zipName, Updater.checksumName]) -> Data {
        let assetList = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/\#(Updater.repository)/releases/download/\#(tag)/\#($0)"}"#
        }
        return Data(#"{"tag_name":"\#(tag)","body":"Calendar fixes","draft":false,"assets":[\#(assetList.joined(separator: ","))]}"#.utf8)
    }

    @Test func comparesVersionsByNumber() {
        #expect(Updater.isNewer("0.1.10", than: "0.1.9"))
        #expect(Updater.isNewer("v0.2.0", than: "0.1.9"))
        #expect(Updater.isNewer("1.0.0", than: "0.9.9"))
        #expect(!Updater.isNewer("0.1.0", than: "0.1.0"))
        #expect(!Updater.isNewer("v0.1.0", than: "0.2.0"))
    }

    @Test func findsTheZipAndChecksumOfANewerRelease() throws {
        let update = try #require(try Updater.update(fromRelease: release(tag: "v0.2.0"), current: "0.1.0"))
        #expect(update.version == "0.2.0" && update.notes == "Calendar fixes")
        #expect(update.zipURL.lastPathComponent == Updater.zipName)
        #expect(update.checksumURL.lastPathComponent == Updater.checksumName)
    }

    @Test func theSameOrAnOlderReleaseIsNoUpdate() throws {
        #expect(try Updater.update(fromRelease: release(tag: "v0.1.0"), current: "0.1.0") == nil)
        #expect(try Updater.update(fromRelease: release(tag: "v0.0.9", assets: []), current: "0.1.0") == nil)
    }

    @Test func aReleaseWithoutTheZipOrAnUnknownAnswerIsAnError() {
        #expect(throws: UpdateError.missingAsset(Updater.checksumName, tag: "v0.2.0")) {
            try Updater.update(fromRelease: release(tag: "v0.2.0", assets: [Updater.zipName]), current: "0.1.0")
        }
        #expect(throws: UpdateError.unreadableRelease(#"{"message":"Not Found"}"#)) {
            try Updater.update(fromRelease: Data(#"{"message":"Not Found"}"#.utf8), current: "0.1.0")
        }
    }

    @Test func readsTheShasumLine() throws {
        let hash = String(repeating: "ab12", count: 16)
        #expect(try Updater.checksum(from: Data("\(hash.uppercased())  m_notch.zip\n".utf8)) == hash)
        #expect(throws: UpdateError.unreadableChecksum("not a hash")) { try Updater.checksum(from: Data("not a hash".utf8)) }
    }
}
