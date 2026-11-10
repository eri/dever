import XCTest
@testable import Dever

@MainActor
final class ResourceCacheTests: XCTestCase {
    private struct Boom: Error {}

    private func cache() -> (ResourceCache<String, Int>, clock: () -> Void, calls: () -> Int, fetch: () async throws -> Int) {
        let cache = ResourceCache<String, Int>()
        var time = Date(timeIntervalSince1970: 1_000)
        cache.now = { time }
        var calls = 0
        return (cache, { time += 10 }, { calls }, { calls += 1; return calls })
    }

    func testFreshValueIsServedWithoutFetching() async throws {
        let (cache, tick, calls, fetch) = cache()
        let first = try await cache.value("a", maxAge: 30, fetch: fetch)
        tick()
        let second = try await cache.value("a", maxAge: 30, fetch: fetch)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        XCTAssertEqual(calls(), 1)
    }

    func testStaleValueIsFetchedAgain() async throws {
        let (cache, tick, calls, fetch) = cache()
        _ = try await cache.value("a", maxAge: 5, fetch: fetch)
        tick()
        let second = try await cache.value("a", maxAge: 5, fetch: fetch)
        XCTAssertEqual(second, 2)
        XCTAssertEqual(calls(), 2)
        XCTAssertEqual(cache.fetchedAt("a"), Date(timeIntervalSince1970: 1_010))
    }

    func testKeysAreIndependent() async throws {
        let (cache, _, calls, fetch) = cache()
        _ = try await cache.value("a", maxAge: 30, fetch: fetch)
        _ = try await cache.value("b", maxAge: 30, fetch: fetch)
        XCTAssertEqual(calls(), 2)
        XCTAssertEqual(cache.value("a"), 1)
        XCTAssertEqual(cache.value("b"), 2)
    }

    func testConcurrentReadersShareOneFetch() async throws {
        let cache = ResourceCache<String, Int>()
        var calls = 0
        let fetch: () async throws -> Int = {
            calls += 1
            try await Task.sleep(nanoseconds: 50_000_000)
            return 7
        }
        async let a = cache.value("a", maxAge: 30, fetch: fetch)
        async let b = cache.value("a", maxAge: 30, fetch: fetch)
        async let c = cache.value("a", maxAge: 30, fetch: fetch)
        let all = try await [a, b, c]
        XCTAssertEqual(all, [7, 7, 7])
        XCTAssertEqual(calls, 1)
    }

    func testFailedRefreshKeepsTheValueAndSaysSo() async throws {
        let (cache, tick, _, fetch) = cache()
        _ = try await cache.value("a", maxAge: 5, fetch: fetch)
        tick()
        do {
            _ = try await cache.value("a", maxAge: 5) { throw Boom() }
            XCTFail("the failure should be thrown")
        } catch {}
        XCTAssertEqual(cache.value("a"), 1)
        XCTAssertNotNil(cache.failure("a"))
        // Still as old as its last successful read.
        XCTAssertEqual(cache.fetchedAt("a"), Date(timeIntervalSince1970: 1_000))
        // The next success clears the failure.
        _ = try await cache.value("a", maxAge: 5, fetch: fetch)
        XCTAssertNil(cache.failure("a"))
        XCTAssertEqual(cache.value("a"), 2)
    }

    func testFailedFirstFetchLeavesNothing() async {
        let cache = ResourceCache<String, Int>()
        do { _ = try await cache.value("a", maxAge: 5) { throw Boom() }; XCTFail() } catch {}
        XCTAssertNil(cache.value("a"))
        XCTAssertNil(cache.failure("a"))
    }

    func testAFetchAfterAFailureIsTriedAgain() async throws {
        let cache = ResourceCache<String, Int>()
        do { _ = try await cache.value("a", maxAge: 5) { throw Boom() } } catch {}
        let value = try await cache.value("a", maxAge: 5) { 3 }
        XCTAssertEqual(value, 3)
    }

    func testInvalidateForcesAFetchButKeepsTheValue() async throws {
        let (cache, _, calls, fetch) = cache()
        _ = try await cache.value("a", maxAge: 30, fetch: fetch)
        cache.invalidate("a")
        XCTAssertEqual(cache.value("a"), 1)
        XCTAssertFalse(cache.isFresh("a", maxAge: 30))
        let again = try await cache.value("a", maxAge: 30, fetch: fetch)
        XCTAssertEqual(again, 2)
        XCTAssertEqual(calls(), 2)
        XCTAssertTrue(cache.isFresh("a", maxAge: 30))
    }

    func testUpdateChangesTheValueInPlace() async throws {
        let (cache, _, _, fetch) = cache()
        _ = try await cache.value("a", maxAge: 30, fetch: fetch)
        var changes = 0
        cache.onChange = { changes += 1 }
        cache.update("a") { $0 = 42 }
        cache.update("missing") { $0 = 1 }
        XCTAssertEqual(cache.value("a"), 42)
        XCTAssertNil(cache.value("missing"))
        XCTAssertEqual(changes, 1)
    }

    func testOnChangeFiresForReadsFailuresAndRemovals() async throws {
        let (cache, tick, _, fetch) = cache()
        var changes = 0
        cache.onChange = { changes += 1 }
        _ = try await cache.value("a", maxAge: 5, fetch: fetch)          // 1: read landed
        _ = try await cache.value("a", maxAge: 5, fetch: fetch)          // fresh: nothing
        tick()
        do { _ = try await cache.value("a", maxAge: 5) { throw Boom() } } catch {}   // 2: failure
        cache.removeAll()                                                  // 3
        cache.removeAll()                                                  // empty: nothing
        XCTAssertEqual(changes, 3)
    }
}
