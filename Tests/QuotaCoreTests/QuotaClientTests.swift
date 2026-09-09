import XCTest
@testable import QuotaCore

final class QuotaClientTests: XCTestCase {
    // Tests the actual stdio transport against a deterministic external peer.
    private func peer(_ code: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        try code.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testHandshakeReadAndPartialLinesProduceQuota() throws {
        let file = try peer("""
import sys,json,time
a=json.loads(sys.stdin.readline())
assert a['method']=='initialize'
print(json.dumps({'id':a['id'],'result':{}}),flush=True)
assert json.loads(sys.stdin.readline())['method']=='initialized'
b=json.loads(sys.stdin.readline())
assert b['method']=='account/rateLimits/read'
s=json.dumps({'id':b['id'],'result':{'rateLimits':{'primary':{'usedPercent':23}}}})+'\\n'
sys.stdout.write(s[:25]);sys.stdout.flush();time.sleep(0.04)
sys.stdout.write(s[25:]);sys.stdout.flush()
time.sleep(2)
""")
        let done = expectation(description: "live transport parsed quota")
        let client = QuotaClient(executableURL: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [file.path], timeout: 2)
        client.onSnapshot = { snapshot in
            XCTAssertEqual(snapshot.buckets.first?.primary?.remainingPercent, 77)
            done.fulfill()
        }
        client.refresh()
        wait(for: [done], timeout: 4)
        client.stop()
        XCTAssertFalse(client.isRunning)
    }

    func testUnresponsiveServerReportsTimeoutAndStops() throws {
        let file = try peer("import time;time.sleep(4)")
        let done = expectation(description: "timeout surfaced")
        let client = QuotaClient(executableURL: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [file.path], timeout: 0.15)
        client.onStatus = { message, busy in
            if message != nil { XCTAssertFalse(busy); done.fulfill() }
        }
        client.refresh()
        wait(for: [done], timeout: 2)
        client.stop()
        XCTAssertFalse(client.isRunning)
    }

    func testRemoteErrorIsSanitizedAndNeverShownAsQuota() throws {
        let file = try peer("""
import sys,json,time
a=json.loads(sys.stdin.readline())
print(json.dumps({'id':a['id'],'error':{'code':-1,'message':'SECRET-UPSTREAM-TEXT'}}),flush=True)
time.sleep(1)
""")
        let done = expectation(description: "error surfaced without raw response")
        let client = QuotaClient(executableURL: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [file.path], timeout: 1)
        client.onSnapshot = { _ in XCTFail("Errors must not become success") }
        client.onStatus = { message, _ in
            if let message { XCTAssertFalse(message.contains("SECRET")); done.fulfill() }
        }
        client.refresh()
        wait(for: [done], timeout: 3)
        client.stop()
    }
}
