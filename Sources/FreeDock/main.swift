import Cocoa

private let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
