//
//  AsyncSemaphore.swift
//  MacBar
//

import Foundation

/// A lightweight async-compatible counting semaphore.
final class AsyncSemaphore: @unchecked Sendable {
    private final class Waiter: @unchecked Sendable {
        var continuation: CheckedContinuation<Void, Error>?
        var isFinished = false
    }

    private let lock = NSLock()
    private var count: Int
    private var waiters = [Waiter]()

    init(value: Int) {
        self.count = value
    }

    /// Waits for a permit, throwing `CancellationError` if the current task
    /// is cancelled before acquiring one.
    func waitUnlessCancelled() async throws {
        try Task.checkCancellation()

        let acquiredFast: Bool = lock.withLock {
            if count > 0, waiters.isEmpty {
                count -= 1
                return true
            }
            return false
        }
        if acquiredFast {
            return
        }

        let waiter = Waiter()
        try await withTaskCancellationHandler {
            try await acquire(waiter: waiter)
        } onCancel: {
            cancel(waiter: waiter)
        }
    }

    private func acquire(waiter: Waiter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if waiter.isFinished {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            if count > 0 {
                count -= 1
                waiter.isFinished = true
                lock.unlock()
                continuation.resume()
                return
            }
            waiter.continuation = continuation
            waiters.append(waiter)
            lock.unlock()
        }
    }

    private func cancel(waiter: Waiter) {
        lock.lock()
        if waiter.isFinished {
            lock.unlock()
            return
        }
        waiter.isFinished = true
        let continuation = waiter.continuation
        waiter.continuation = nil
        if continuation != nil {
            waiters.removeAll { $0 === waiter }
        }
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }

    /// Releases a permit, waking the next waiting task if any.
    @discardableResult
    func signal() -> Bool {
        lock.lock()
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            if !waiter.isFinished, let continuation = waiter.continuation {
                waiter.isFinished = true
                waiter.continuation = nil
                lock.unlock()
                continuation.resume()
                return true
            }
        }
        count += 1
        lock.unlock()
        return false
    }
}
