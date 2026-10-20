import AppKit

// Writes to a child that already exited (claude, log stream) or to a closed socket must fail, not kill the
// app; the pipes and sockets also opt out one by one.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
