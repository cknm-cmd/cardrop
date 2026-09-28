// Main executable of Cardrop.app.
//
// macOS grants "Removable Volumes" access and notification permission per app. Running the
// worker through this tiny app means those permissions belong to Cardrop, not to /bin/bash.
//
//   cardrop-helper                         run the worker (this is what launchd starts)
//   cardrop-helper notify <title> <body> [sound]
//   cardrop-helper notify-check            print "allowed", "denied" or "undecided"
import Foundation
import UserNotifications

let args = CommandLine.arguments
let center = UNUserNotificationCenter.current()
var notifyFailed = false

func waitFor(_ work: (@escaping () -> Void) -> Void) {
    let done = DispatchSemaphore(value: 0)
    work { done.signal() }
    _ = done.wait(timeout: .now() + 60)
}

if args.count >= 2, args[1] == "notify-check" {
    waitFor { finish in
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional: print("allowed")
            case .denied: print("denied")
            default: print("undecided")
            }
            finish()
        }
    }
    exit(0)
}

if args.count >= 4, args[1] == "notify" {
    waitFor { finish in
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                FileHandle.standardError.write(Data("Notifications not allowed: \(error?.localizedDescription ?? "denied")\n".utf8))
                notifyFailed = true
                finish()
                return
            }
            let content = UNMutableNotificationContent()
            content.title = args[2]
            content.body = args[3]
            content.sound = args.count >= 5
                ? UNNotificationSound(named: UNNotificationSoundName(args[4]))
                : .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { _ in finish() }
        }
    }
    exit(notifyFailed ? 1 : 0)
}

// Default: run the worker. It lives outside the bundle so updating it never changes this app's
// code signature (which would make macOS ask for permissions again). Spawn rather than exec, so
// this app stays the "responsible" process for everything the worker starts.
let worker = NSHomeDirectory() + "/Library/Application Support/cardrop/cardrop-run.sh"
guard FileManager.default.fileExists(atPath: worker) else {
    FileHandle.standardError.write(Data("cardrop worker not found at \(worker). Re-run install.sh.\n".utf8))
    exit(1)
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = [worker]
do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    exit(1)
}
