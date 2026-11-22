import Foundation
import Testing
@testable import IceMacOS27Core

@Suite("AsyncSemaphore")
struct AsyncSemaphoreTests {
    @Test("Immediate acquire and release without suspension")
    func immediateAcquireAndRelease() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        try await semaphore.waitUnlessCancelled()
        let wokeWaiter = semaphore.signal()
        #expect(wokeWaiter == false)
    }

    @Test("Serializes concurrent tasks in FIFO order")
    func serializesConcurrentTasks() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        let log = LockedArray<Int>()

        try await semaphore.waitUnlessCancelled()

        let task1 = Task {
            try await semaphore.waitUnlessCancelled()
            log.append(1)
            semaphore.signal()
        }
        // Yield briefly so task1 registers first.
        try await Task.sleep(for: .milliseconds(20))

        let task2 = Task {
            try await semaphore.waitUnlessCancelled()
            log.append(2)
            semaphore.signal()
        }
        try await Task.sleep(for: .milliseconds(20))

        #expect(log.snapshot() == [])
        semaphore.signal()

        try await task1.value
        try await task2.value
        #expect(log.snapshot() == [1, 2])
    }

    @Test("Cancelled waiter throws CancellationError and does not leak permits")
    func cancelledWaiterDoesNotLeakPermit() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        try await semaphore.waitUnlessCancelled()

        let waitingTask = Task {
            try await semaphore.waitUnlessCancelled()
        }
        try await Task.sleep(for: .milliseconds(20))
        waitingTask.cancel()

        do {
            try await waitingTask.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        }

        // Releasing the original permit should leave count == 1 so the next acquire succeeds immediately.
        let woke = semaphore.signal()
        #expect(woke == false)
        try await semaphore.waitUnlessCancelled()
        semaphore.signal()
    }
}

private final class LockedArray<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items = [Element]()

    func append(_ item: Element) {
        lock.withLock { items.append(item) }
    }

    func snapshot() -> [Element] {
        lock.withLock { items }
    }
}
