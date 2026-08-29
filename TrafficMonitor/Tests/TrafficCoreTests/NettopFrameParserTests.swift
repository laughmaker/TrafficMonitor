import Foundation
import Testing
@testable import TrafficCore

struct NettopFrameParserTests {
    private let parser = NettopFrameParser(sampleDuration: 2)

    @Test func parsesOrdinaryProcess() throws {
        let sample = try #require(parser.parseLine("Safari.123,2048,1024"))

        #expect(sample.pid == 123)
        #expect(sample.processName == "Safari")
        #expect(sample.receivedBytesPerSecond == 1024)
        #expect(sample.sentBytesPerSecond == 512)
    }

    @Test func preservesDotsInProcessName() throws {
        let sample = try #require(parser.parseLine("com.apple.WebKit.Networking.987,4096,0"))

        #expect(sample.pid == 987)
        #expect(sample.processName == "com.apple.WebKit.Networking")
    }

    @Test func parsesQuotedCommaAndEscapedQuote() throws {
        let sample = try #require(parser.parseLine("\"Tool, \"\"Preview\"\".42\",100,50"))

        #expect(sample.pid == 42)
        #expect(sample.processName == "Tool, \"Preview\"")
    }

    @Test func rejectsHeaderAndMalformedRows() {
        #expect(parser.parseLine(",bytes_in,bytes_out,") == nil)
        #expect(parser.parseLine("process,bytes_in,bytes_out") == nil)
        #expect(parser.parseLine("missing-pid,10,20") == nil)
        #expect(parser.parseLine("App.1,not-a-number,20") == nil)
    }

    @Test func clampsNegativeCounters() throws {
        let sample = try #require(parser.parseLine("App.7,-1,-20"))

        #expect(sample.receivedBytes == 0)
        #expect(sample.sentBytes == 0)
    }

    @Test func aggregatesAFrame() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let snapshot = parser.parseFrame(
            ["A.1,2048,1024", "B.2,1024,3072"],
            timestamp: timestamp
        )

        #expect(snapshot.timestamp == timestamp)
        #expect(snapshot.totalReceivedBytesPerSecond == 1536)
        #expect(snapshot.totalSentBytesPerSecond == 2048)
    }

    @Test func parsesActualNettopShapeWithTrailingComma() throws {
        let sample = try #require(parser.parseLine("Google Chrome H.28280,54123026,25757540,"))

        #expect(sample.pid == 28280)
        #expect(sample.processName == "Google Chrome H")
        #expect(sample.receivedBytes == 54_123_026)
        #expect(sample.sentBytes == 25_757_540)
    }
}
