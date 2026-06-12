import Foundation

@objc public class BGQueue: NSObject {

    private var items: [Any] = []
    private let lock = NSLock()

    @objc public func enqueue(_ item: Any) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    @objc public func dequeue() -> Any? {
        lock.lock()
        defer { lock.unlock() }
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    @objc public func peek() -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return items.first
    }

    @objc public func isEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty
    }

    @objc public func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    @objc public func clear() {
        lock.lock()
        items.removeAll()
        lock.unlock()
    }

    @objc public func allItems() -> [Any] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}
