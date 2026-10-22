import XCTest
@testable import KopiKit

final class ClipKindTests: XCTestCase {
    func testClassify() {
        XCTAssertEqual(ClipKind.classify("https://github.com/sozercan/kaset"), .link)
        XCTAssertEqual(ClipKind.classify("github.com/foo"), .link)
        XCTAssertEqual(ClipKind.classify("#825882"), .color)
        XCTAssertEqual(ClipKind.classify("#fff"), .color)
        XCTAssertEqual(ClipKind.classify("rgb(10, 20, 30)"), .color)
        XCTAssertEqual(ClipKind.classify("melvern@example.com"), .email)
        XCTAssertEqual(ClipKind.classify("1,250.50"), .number)
        XCTAssertEqual(ClipKind.classify("/Users/melvernmogens/Code/kopi"), .path)
        XCTAssertEqual(ClipKind.classify("let config = AppConfig(name: \"prod\") { x in x }"), .code)
        XCTAssertEqual(ClipKind.classify("npm install foo && npm run build"), .code)
        XCTAssertEqual(ClipKind.classify("Thanks for reaching out! I'll get back to you shortly."), .text)
        XCTAssertEqual(ClipKind.classify("hermes auth login openai-codex"), .text)
        XCTAssertEqual(ClipKind.classify("   "), .text)
    }

    func testTitleCollapsesWhitespaceAndUsesName() {
        XCTAssertEqual(Clip(content: "\n\n  hello    world \nsecond").title, "hello world")
        XCTAssertEqual(Clip(content: "abc", name: "  My key ").title, "My key")
        XCTAssertEqual(Clip(content: "abc", name: "   ").title, "abc")
    }
}

final class ClipStoreTests: XCTestCase {
    var path: String!
    override func setUp() { path = NSTemporaryDirectory() + "kopi-test-\(UUID().uuidString).sqlite" }
    override func tearDown() { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }

    func testAddDedupesAndOrdersNewestFirst() throws {
        let s = try ClipStore(path: path)
        let t = Date(timeIntervalSince1970: 1000)
        let a = s.add("alpha", at: t)!
        _ = s.add("beta", at: t.addingTimeInterval(1))
        XCTAssertEqual(s.clips.map(\.content), ["beta", "alpha"])
        let a2 = s.add("alpha", at: t.addingTimeInterval(2))
        XCTAssertEqual(a, a2)
        XCTAssertEqual(s.clips.map(\.content), ["alpha", "beta"])
        XCTAssertNil(s.add("  \n "))
        XCTAssertEqual(s.clips.count, 2)
    }

    func testPersistsAcrossReopen() throws {
        do {
            let s = try ClipStore(path: path)
            let id = s.add("keep me")!
            s.setPinned(id, true)
            s.rename(id, to: "Key")
        }
        let s2 = try ClipStore(path: path)
        XCTAssertEqual(s2.clips.count, 1)
        XCTAssertEqual(s2.clips[0].name, "Key")
        XCTAssertTrue(s2.clips[0].pinned)
    }

    func testPinnedFirstAndPinOrder() throws {
        let s = try ClipStore(path: path)
        let t = Date(timeIntervalSince1970: 1000)
        let a = s.add("a", at: t)!, b = s.add("b", at: t + 1)!, c = s.add("c", at: t + 2)!
        s.setPinned(a, true, toTop: true)
        s.setPinned(b, true, toTop: true)
        XCTAssertEqual(s.clips.map(\.content), ["b", "a", "c"])
        s.setPinned(c, true, toTop: false)
        XCTAssertEqual(s.pinned.map(\.content), ["b", "a", "c"])
        s.movePinned(c, by: -1)
        XCTAssertEqual(s.pinned.map(\.content), ["b", "c", "a"])
        s.movePinned(b, by: -1) // already top: no-op
        XCTAssertEqual(s.pinned.map(\.content), ["b", "c", "a"])
        // Using a pinned clip doesn't reorder pins.
        s.markUsed(a)
        XCTAssertEqual(s.pinned.map(\.content), ["b", "c", "a"])
    }

    func testHistoryLimitNeverDropsPins() throws {
        let s = try ClipStore(path: path, historyLimit: 3)
        let t = Date(timeIntervalSince1970: 1000)
        let first = s.add("0", at: t)!
        s.setPinned(first, true)
        for i in 1...6 { s.add("\(i)", at: t + Double(i)) }
        XCTAssertEqual(s.history.map(\.content), ["6", "5", "4"])
        XCTAssertEqual(s.pinned.map(\.content), ["0"])
        let s2 = try ClipStore(path: path, historyLimit: 3)
        XCTAssertEqual(s2.clips.count, 4)
    }

    func testMarkUsedBumpsUnpinned() throws {
        let s = try ClipStore(path: path)
        let t = Date(timeIntervalSince1970: 1000)
        let a = s.add("a", at: t)!
        s.add("b", at: t + 1)
        s.markUsed(a, at: t + 2)
        XCTAssertEqual(s.clips.map(\.content), ["a", "b"])
        XCTAssertEqual(s.clip(a)?.pasteCount, 1)
        let b = s.clips[1].id
        s.markUsed(b, at: t + 3, bump: false)
        XCTAssertEqual(s.clips.map(\.content), ["a", "b"])
    }

    func testEditMergesDuplicateAndDropsRTF() throws {
        let s = try ClipStore(path: path)
        let a = s.add("one", rtf: Data([1, 2]))!
        let b = s.add("two")!
        s.rename(a, to: "Named")
        s.edit(a, content: "two")
        XCTAssertNil(s.clip(b))
        XCTAssertEqual(s.clip(a)?.content, "two")
        XCTAssertNil(s.clip(a)?.rtf)
        XCTAssertEqual(s.clip(a)?.name, "Named")
        XCTAssertEqual(s.clips.count, 1)
    }

    func testDeleteAllKeepsPinsByDefault() throws {
        let s = try ClipStore(path: path)
        let a = s.add("a")!
        s.add("b")
        s.setPinned(a, true)
        s.deleteAll()
        XCTAssertEqual(s.clips.map(\.content), ["a"])
        s.deleteAll(includingPinned: true)
        XCTAssertTrue(s.clips.isEmpty)
    }

    func testImportSkipsExisting() throws {
        let s = try ClipStore(path: path)
        s.add("dup")
        let n = s.importClips([Clip(content: "dup"), Clip(content: "new", name: "N", pinned: true), Clip(content: "  ")])
        XCTAssertEqual(n, 1)
        XCTAssertEqual(s.pinned.first?.name, "N")
    }

    func testMeta() throws {
        let s = try ClipStore(path: path)
        XCTAssertNil(s.meta("x"))
        s.setMeta("x", "1"); s.setMeta("x", "2")
        XCTAssertEqual(s.meta("x"), "2")
    }
}

final class SearchTests: XCTestCase {
    let clips = [
        Clip(id: 1, content: "https://api.example.com/v2/users", sourceBundle: "com.google.Chrome", sourceName: "Google Chrome"),
        Clip(id: 2, content: "ssh-rsa AAAAB3Nza", name: "Work SSH key", pinned: true),
        Clip(id: 3, content: "Café meeting moved to 3pm", sourceName: "WhatsApp"),
        Clip(id: 4, content: "export API_KEY=\"prod_x\" && curl -H x", sourceName: "Terminal"),
    ]

    func testMultiTokenAndDiacritics() {
        XCTAssertEqual(ClipSearch.filter(clips, query: "cafe 3pm").map(\.id), [3])
        XCTAssertEqual(ClipSearch.filter(clips, query: "api").map(\.id).sorted(), [1, 4])
        XCTAssertEqual(ClipSearch.filter(clips, query: "zzz").count, 0)
        XCTAssertEqual(ClipSearch.filter(clips, query: "").count, 4)
    }

    func testNameAndSourceMatch() {
        XCTAssertEqual(ClipSearch.filter(clips, query: "ssh key").map(\.id), [2])
        XCTAssertEqual(ClipSearch.filter(clips, query: "whatsapp").map(\.id), [3])
    }

    func testOperators() {
        XCTAssertEqual(ClipSearch.filter(clips, query: "app:chrome").map(\.id), [1])
        XCTAssertEqual(ClipSearch.filter(clips, query: "type:link").map(\.id), [1])
        XCTAssertEqual(ClipSearch.filter(clips, query: "type:code").map(\.id), [4])
        XCTAssertEqual(ClipSearch.filter(clips, query: "is:pinned").map(\.id), [2])
    }

    func testPinnedRankFirst() {
        let r = ClipSearch.filter(clips, query: "a")
        XCTAssertEqual(r.first?.id, 2)
    }

    func testHighlightRanges() {
        let text = "Café cafe CAFE"
        XCTAssertEqual(ClipSearch.highlightRanges(in: text, query: "cafe").count, 3)
    }

    func testRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RelativeTime.short(now, now: now), "now")
        XCTAssertEqual(RelativeTime.short(now - 300, now: now), "5m")
        XCTAssertEqual(RelativeTime.short(now - 7200, now: now), "2h")
        XCTAssertEqual(RelativeTime.short(now - 86400 * 3, now: now), "3d")
    }
}

final class RulesTests: XCTestCase {
    func testIgnore() {
        XCTAssertTrue(PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], sourceBundle: nil, ignoredBundles: [], ignoreConcealed: true))
        XCTAssertFalse(PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], sourceBundle: nil, ignoredBundles: [], ignoreConcealed: false))
        XCTAssertTrue(PasteboardRules.shouldIgnore(types: [PasteboardRules.ownMarker], sourceBundle: nil, ignoredBundles: [], ignoreConcealed: false))
        XCTAssertTrue(PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text"], sourceBundle: "com.bitwarden.desktop", ignoredBundles: ["com.bitwarden.desktop"], ignoreConcealed: true))
        XCTAssertFalse(PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text"], sourceBundle: "com.apple.Notes", ignoredBundles: ["com.bitwarden.desktop"], ignoreConcealed: true))
    }

    func testHotKeyDisplay() {
        XCTAssertEqual(HotKeySpec.defaultPanel.display, "⌃Space")
        XCTAssertEqual(HotKeySpec.defaultMenu.display, "⌃⌥Space")
        XCTAssertEqual(HotKeySpec(keyCode: 9, modifiers: HotKeySpec.command | HotKeySpec.shift).display, "⇧⌘V")
    }
}

final class ImporterTests: XCTestCase {
    func testReadsCoreDataSchema() throws {
        let dir = NSTemporaryDirectory() + "kopi-cc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let p = dir + "/copyclip.sqlite"
        let db = try SQLiteDB(path: p)
        try db.exec("""
        CREATE TABLE ZCLIPPING ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZPINNED INTEGER, ZTOTALPASTES INTEGER, ZSOURCE INTEGER, ZDATERECORDED TIMESTAMP, ZCONTENTS VARCHAR, ZDISPLAYTITLE VARCHAR, ZTYPE VARCHAR, ZATTRIBUTEDCONTENTS BLOB );
        CREATE TABLE ZSOURCEAPP ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZISBLACKLISTED INTEGER, ZBUNDLE VARCHAR, ZNAME VARCHAR, ZICON BLOB );
        INSERT INTO ZSOURCEAPP VALUES (1,2,1,0,'net.whatsapp.WhatsApp','\u{200E}WhatsApp',NULL);
        INSERT INTO ZCLIPPING VALUES (1,1,1,1,3,1,814382957.1,'hello','Greeting','public.utf8-plain-text',NULL);
        INSERT INTO ZCLIPPING VALUES (2,1,1,0,0,NULL,814382000.0,'world',NULL,'public.utf8-plain-text',NULL);
        """)
        let clips = try CopyClipImporter.read(path: p)
        XCTAssertEqual(clips.map(\.content), ["world", "hello"])
        let h = clips[1]
        XCTAssertEqual(h.name, "Greeting")
        XCTAssertTrue(h.pinned)
        XCTAssertEqual(h.pasteCount, 3)
        XCTAssertEqual(h.sourceName, "WhatsApp")
        XCTAssertEqual(h.sourceBundle, "net.whatsapp.WhatsApp")
        XCTAssertEqual(h.created.timeIntervalSince1970, 814382957.1 + 978_307_200, accuracy: 0.01)
    }
}

final class TitleTests: XCTestCase {
    func testDecorativeRulesTrimmed() {
        XCTAssertEqual(Clip(content: "── Hermes error details ──\nfoo").title, "Hermes error details")
        XCTAssertEqual(Clip(content: "- item one").title, "item one")
        XCTAssertEqual(Clip(content: "---").title, "---")
    }
    func testTerminal() {
        XCTAssertTrue(ClipKind.looksLikeTerminal("Last login: Thu Oct 22 on ttys000\nfoo"))
        XCTAssertTrue(ClipKind.looksLikeTerminal("melvern@mbp ~ % ls\nfile"))
        XCTAssertFalse(ClipKind.looksLikeTerminal("Meeting moved to 3pm"))
    }
}
