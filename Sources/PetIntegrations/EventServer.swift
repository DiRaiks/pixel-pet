import Darwin
import Foundation

/// Unix-socket server for hook payloads: one connection carries one event, read until EOF.
/// Runs on its own serial queue; the handler is called there, so hop to the main actor yourself.
/// A permission request keeps its connection open: the handler gets a `HookReply` to answer through.
/// Everything else is closed right after reading.
public final class EventServer: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable {
        case pathOccupied(String)
        case pathTooLong(String)
        case system(String, Int32)
    }

    /// Hook payloads include tool output (a big Read or Bash result), so the cap is generous.
    static let maxPayload = 16 << 20
    /// Total time one connection may take; a stuck client can delay other hooks by at most this much.
    public static let connectionDeadline: TimeInterval = 1

    private let path: String
    private let handler: @Sendable (Data, HookReply?) -> Void
    /// How long a waiting hook's connection may stay open if nobody answers (a safety net: the app lets go
    /// sooner, at `PermissionWait.window`).
    public static let replyDeadline: TimeInterval = 66
    private let queue = DispatchQueue(label: "dev.pixelpet.events")
    // Touched only on `queue` (or before start / after stop).
    private var source: DispatchSourceRead?
    private var inode: ino_t = 0

    public init(path: String, handler: @escaping @Sendable (Data, HookReply?) -> Void) {
        self.path = path
        self.handler = handler
    }

    /// For callers that never answer: a waiting hook is let go at once.
    public convenience init(path: String, handler: @escaping @Sendable (Data) -> Void) {
        self.init(path: path) { data, reply in
            reply?.send(nil)
            handler(data)
        }
    }

    public func start() throws {
        // `self.` spelled out: Swift 6.3 takes a bare `source` for the local declared further down.
        guard queue.sync(execute: { self.source == nil }) else { return }
        try clearStaleSocket()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Error.system("socket", errno) }
        do {
            try bind(fd)
        } catch {
            close(fd)
            throw error
        }
        do {
            guard chmod(path, 0o600) == 0 else { throw Error.system("chmod", errno) }
            guard listen(fd, 128) == 0 else { throw Error.system("listen", errno) }
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else { throw Error.system("fcntl", errno) }
        } catch {
            close(fd)
            unlink(path)
            throw error
        }
        var info = stat()
        if lstat(path, &info) == 0 { inode = info.st_ino }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(fd) }
        source.setCancelHandler { close(fd) }
        queue.sync { self.source = source }
        source.resume()
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
        }
        // Only remove the socket file if it is still ours (a newer server may have replaced it).
        var info = stat()
        if lstat(path, &info) == 0, info.st_ino == inode { unlink(path) }
    }

    private func bind(_ fd: Int32) throws {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw Error.pathTooLong(path) }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, size) }
        }
        guard rc == 0 else { throw Error.system("bind", errno) }
    }

    /// A dead socket from a crashed run is replaced. A live one (another pet is running) and
    /// any other kind of file are left alone.
    private func clearStaleSocket() throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw Error.pathOccupied(path) }
        if (try? SocketClient.probe(path)) == true { throw Error.pathOccupied(path) }
        unlink(path)
    }

    private func acceptPending(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            guard let data = read(client), !data.isEmpty else {
                close(client)
                continue
            }
            if Self.waitsForReply(data) {
                handler(data, HookReply(fd: client, deadline: Self.replyDeadline))
            } else {
                handler(data, nil)
                close(client)
            }
        }
    }

    /// Only the permission request waits for an answer; a cheap check before the app parses it properly.
    static func waitsForReply(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["hook_event_name"] as? String == "PermissionRequest"
    }

    /// Reads until EOF with one overall deadline, so a trickling client can't hold the queue for long.
    private func read(_ client: Int32) -> Data? {
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) | O_NONBLOCK)
        let deadline = Date().addingTimeInterval(Self.connectionDeadline)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count <= Self.maxPayload {
            let n = Darwin.read(client, &buffer, buffer.count)
            if n > 0 {
                data.append(contentsOf: buffer[0..<n])
                continue
            }
            if n == 0 { return data }
            guard errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR else { return nil }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var pfd = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            _ = poll(&pfd, 1, Int32(remaining * 1000))
        }
        return nil
    }
}

/// Minimal client, used by tests, the live-socket probe and manual pokes; the real sender is the shell hook.
public enum SocketClient {
    /// True when something is listening on the socket.
    static func probe(_ path: String) throws -> Bool {
        let fd = try connected(to: path)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    /// Returns a connected fd, or -1 when nobody listens (ECONNREFUSED / ENOENT).
    private static func connected(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw EventServer.Error.system("socket", errno) }
        // A server that goes away mid-send gives a failed write, not a SIGPIPE.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw EventServer.Error.pathTooLong(path)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard rc == 0 else {
            let error = errno
            close(fd)
            if error == ECONNREFUSED || error == ENOENT { return -1 }
            throw EventServer.Error.system("connect", error)
        }
        return fd
    }

    public static func send(_ payload: Data, to path: String) throws {
        let fd = try connected(to: path)
        guard fd >= 0 else { throw EventServer.Error.system("connect", ECONNREFUSED) }
        defer { close(fd) }
        try payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                guard n > 0 else { throw EventServer.Error.system("write", errno) }
                offset += n
            }
        }
        shutdown(fd, SHUT_WR)
    }
}

/// The open connection of a hook waiting for the pet's answer. The first `send` wins: it writes the hook's
/// output (or nothing, to let Claude Code ask the usual way) and closes; later calls do nothing. If nobody
/// answers by the deadline it closes empty by itself.
public final class HookReply: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32?
    private var watch: DispatchSourceTimer?
    private var gone: (@Sendable () -> Void)?

    init(fd: Int32, deadline: TimeInterval) {
        self.fd = fd
        // A hook that went away mustn't take the app down with SIGPIPE when the answer comes late, and a peer
        // that stops reading mustn't hold up the caller.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var limit = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        DispatchQueue.global().asyncAfter(deadline: .now() + deadline) { [weak self] in self?.send(nil) }
    }

    deinit {
        watch?.cancel()
        send(nil)
    }

    /// Calls `action` (on a background queue) once the hook is gone without an answer: killed with its
    /// session, Esc in the terminal, Claude Code's own timeout. Checked twice a second while waiting.
    public func onGone(_ action: @escaping @Sendable () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, let fd = lock.withLock({ self.fd }) else { return }
            if Self.peerClosed(fd), lock.withLock({ self.fd != nil }) {
                send(nil)
                action()
            }
        }
        lock.withLock {
            gone = action
            watch = timer
        }
        timer.resume()
    }

    /// The hook half-closes its side after writing; only when it's gone altogether does writing hit EOF.
    static func peerClosed(_ fd: Int32) -> Bool {
        let kq = kqueue()
        guard kq >= 0 else { return false }
        defer { close(kq) }
        var change = kevent(ident: UInt(fd), filter: Int16(EVFILT_WRITE), flags: UInt16(EV_ADD | EV_ONESHOT),
                            fflags: 0, data: 0, udata: nil)
        var event = kevent()
        var zero = timespec(tv_sec: 0, tv_nsec: 0)
        let n = kevent(kq, &change, 1, &event, 1, &zero)
        return n > 0 && event.flags & UInt16(EV_EOF) != 0
    }

    public var isOpen: Bool { lock.withLock { fd != nil } }

    public func send(_ output: Data?) {
        guard let fd = lock.withLock({ () -> Int32? in
            defer {
                self.fd = nil
                watch?.cancel()
                watch = nil
            }
            return self.fd
        }) else { return }
        if let output, !output.isEmpty {
            output.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n <= 0 { break }
                    offset += n
                }
            }
        }
        close(fd)
    }
}
