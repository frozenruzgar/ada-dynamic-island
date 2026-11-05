@testable import Ada
import Foundation
import CoreGraphics
import AdaCore

enum CoreChecks {
    static func main() throws {
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let zero = Date(timeIntervalSince1970: 1_000)
var clock = FocusClock(minutes: 25)
clock.start(at: zero)
clock.pause(at: zero.addingTimeInterval(73))
expect(clock.remaining() == 1427, "Pause preserves remaining time")
clock.start(at: zero.addingTimeInterval(600))
expect(clock.remaining(at: zero.addingTimeInterval(610)) == 1417, "Resume uses the new deadline")
clock = FocusClock(minutes: 1)
clock.start(at: zero)
expect(clock.finishIfNeeded(at: zero.addingTimeInterval(3600)), "Wake after deadline completes")
expect(!clock.finishIfNeeded(at: zero.addingTimeInterval(3601)), "Completion fires once")
expect(clock.completed && clock.progress() == 1 && clock.remaining() == 0, "Completed state is consistent")
clock.start(at: zero.addingTimeInterval(4000))
expect(clock.remaining(at: zero.addingTimeInterval(4000)) == 60 && !clock.completed, "Completed timer restarts")
clock.reset(minutes: 50)
expect(!clock.isRunning && clock.remaining() == 3000, "Reset selects a new duration")
clock = FocusClock(minutes: 25)
clock.start(at: zero)
let restored = try JSONDecoder().decode(FocusClock.self, from: JSONEncoder().encode(clock))
expect(restored.remaining(at: zero.addingTimeInterval(90)) == 1410, "Active session survives serialization")
clock = FocusClock(minutes: 1)
clock.start(at: zero)
clock.pause(at: zero.addingTimeInterval(60))
expect(clock.completed && !clock.isRunning, "Pause at deadline completes")
clock = FocusClock(minutes: 25)
clock.start(at: zero)
clock.adjust(by: 300, at: zero.addingTimeInterval(60))
expect(clock.remaining(at: zero.addingTimeInterval(60)) == 1740, "Extend active timer without pausing")
expect(clock.duration == 1800, "Extended timer updates full duration")
clock.adjust(by: -6000, at: zero.addingTimeInterval(60))
expect(clock.remaining(at: zero.addingTimeInterval(60)) == 1, "Shortening clamps to one second")
clock.pause(at: zero.addingTimeInterval(60))
clock.adjust(by: 300, at: zero.addingTimeInterval(100))
expect(!clock.isRunning && clock.remaining() == 301, "Paused adjustment keeps paused state")
print("PASS: 13 focus clock checks")

let camera = CGRect(x: 620, y: 852, width: 160, height: 48)
let hidden = IslandHoverRegion(panel: nil, camera: camera)
let compact = IslandHoverRegion(panel: CGRect(x: 642, y: 826, width: 116, height: 31), camera: camera)
let expanded = IslandHoverRegion(panel: CGRect(x: 370, y: 600, width: 660, height: 300), camera: camera)
expect(hidden.contains(CGPoint(x: 700, y: 900)), "The camera opens Ada at the display’s top edge")
expect(!hidden.contains(CGPoint(x: 700, y: 838)), "An invisible compact frame cannot open Ada below the camera")
expect(compact.contains(CGPoint(x: 700, y: 838)), "A visible compact control can open Ada")
expect(!compact.contains(CGPoint(x: 840, y: 880)), "Adjacent menu titles do not open the compact island")
expect(expanded.contains(CGPoint(x: 840, y: 880)), "Diagonal travel across the open top band keeps Ada open")
expect(expanded.contains(CGPoint(x: 960, y: 815)), "Controls remain within the open hover region")
expect(expanded.contains(CGPoint(x: 1034, y: 750)), "The open edge includes a small exit margin")
expect(!expanded.contains(CGPoint(x: 1035, y: 750)), "Leaving the panel and its exit margin permits collapse")
expect(!compact.contains(CGPoint(x: 960, y: 815)), "The old expanded bounds cannot reopen a compact island")
print("PASS: 9 camera hover and island boundary checks")

let currentVersion = ApplicationVersion("0.11.0", build: "22")
let sameVersion = ApplicationVersion("0.11", build: "22.0")
expect(currentVersion == sameVersion, "Trailing zeros do not change a release/build version")
expect(ApplicationVersion("0.10.10", build: "1") > ApplicationVersion("0.10.9", build: "999"), "Numeric release comparison precedes build numbers")
let runningCopy = ApplicationInstance(pid: 90000, version: currentVersion, launchedAt: 100)
let newCopy = ApplicationInstance(pid: 10, version: currentVersion, launchedAt: 200)
expect(ApplicationLaunchPolicy.winner(current: newCopy, others: [runningCopy]).pid == runningCopy.pid, "Equal versions keep the old launch even after PID wrap")
expect(ApplicationLaunchPolicy.winner(current: runningCopy, others: [newCopy]).pid == runningCopy.pid, "Concurrent starts agree on one winner")
let olderCopy = ApplicationInstance(pid: 1, version: ApplicationVersion("0.10.6", build: "21"), launchedAt: 50)
expect(ApplicationLaunchPolicy.winner(current: newCopy, others: [olderCopy]).pid == newCopy.pid, "A newer package can take over an old instance")
let newerCopy = ApplicationInstance(pid: 20, version: ApplicationVersion("0.12", build: "1"), launchedAt: 300)
expect(ApplicationLaunchPolicy.winner(current: newCopy, others: [newerCopy]).pid == newerCopy.pid, "An old package never replaces a newer running copy")
expect(ApplicationLaunchPolicy.winner(current: newCopy, others: []).pid == newCopy.pid, "A first launch starts normally")
print("PASS: 7 application version and single-instance launch policy checks")

let hiddenCompletion = FocusCompletionPresentation(islandVisible: false, openPanel: true, notifications: true)
expect(hiddenCompletion.shouldNotify && !hiddenCompletion.shouldOpenPanel, "A hidden island can notify without unhiding itself")
let defaultCompletion = FocusCompletionPresentation(islandVisible: true, openPanel: true, notifications: false)
expect(!defaultCompletion.shouldNotify && defaultCompletion.shouldOpenPanel, "Notifications stay opt-in")
let quietCompletion = FocusCompletionPresentation(islandVisible: false, openPanel: false, notifications: false)
expect(!quietCompletion.shouldNotify && !quietCompletion.shouldOpenPanel, "All explicit quiet preferences are respected")
print("PASS: 3 visible/hidden focus completion presentation checks")

let closedTracking = PointerTrackingPolicy.mode(visible: true, hoverEnabled: true, expanded: false)
expect(closedTracking == .eventsOnly, "A closed island listens for events")
expect(PointerTrackingPolicy.timerInterval(mode: closedTracking, globalMonitorAvailable: true) == nil, "Closed event tracking has no recurring pointer timer")
expect(PointerTrackingPolicy.timerInterval(mode: closedTracking, globalMonitorAvailable: false) == 0.2, "A failed monitor keeps a bounded hover fallback")
let openTracking = PointerTrackingPolicy.mode(visible: true, hoverEnabled: true, expanded: true)
expect(PointerTrackingPolicy.timerInterval(mode: openTracking, globalMonitorAvailable: true) == 0.06, "Open panels retain exit and interaction checks")
expect(PointerTrackingPolicy.mode(visible: false, hoverEnabled: true, expanded: false) == .disabled, "Hidden islands stop pointer tracking")
expect(PointerTrackingPolicy.mode(visible: true, hoverEnabled: false, expanded: true) == .disabled, "Click-only mode needs no pointer timer")
print("PASS: 6 event-driven pointer lifecycle and fallback policy checks")

expect(BackgroundMotionPolicy.permitsAnimation(expanded: true, keyWindow: true, pointerInside: true, lowPower: false, batteryPercent: 20, reduceMotion: false), "Motion permitted at threshold while interacting")
for flag in 0..<6 {
    expect(!BackgroundMotionPolicy.permitsAnimation(expanded: flag != 0, keyWindow: flag != 1, pointerInside: flag != 2, lowPower: flag == 3, batteryPercent: flag == 4 ? 19 : 100, reduceMotion: flag == 5), "Every motion stop condition overrides animation")
}
print("PASS: background motion key-window, pointer, battery, low-power and accessibility policy")

let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), safeTop: 38, statusBarHeight: 24, auxiliaryLeft: CGRect(x: 0, y: 944, width: 660, height: 38), auxiliaryRight: CGRect(x: 852, y: 944, width: 660, height: 38))
expect(screen.notchWidth == 192 && screen.cameraCenterX(attached: true) == 756, "Physical camera gap geometry")
let attachedFrame = screen.panelFrame(size: CGSize(width: 660, height: 280), attached: true, flushToTop: true, floatingGap: 8)
expect(attachedFrame == CGRect(x: 426, y: 702, width: 660, height: 280), "Attached panel covers top in logical points")
expect(screen.cameraInputFrame(attached: true)?.contains(CGPoint(x: 756, y: 981)) == true, "Hover includes camera top")
let external = ScreenGeometry(frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056), safeTop: 0, statusBarHeight: 24)
expect(external.notchWidth == 0 && external.cameraInputFrame(attached: false) == nil, "Notchless screen has no camera hit target")
expect(external.panelFrame(size: CGSize(width: 660, height: 250), attached: false, flushToTop: false, floatingGap: 8) == CGRect(x: -1290, y: 598, width: 660, height: 250), "Negative-origin external screen placement")
expect(screen.panelFrame(size: CGSize(width: 116, height: 31), attached: true, flushToTop: false, floatingGap: 0).maxY == 942, "Closed camera-band clearance preserved")
print("PASS: notched/notchless geometry, multi-display origins and point-based placement independent of backing scale")


expect(TypographyMetrics.pointSize(base: 8, scale: 1) == 10, "Smallest type is ten points")
expect(TypographyMetrics.pointSize(base: 10, scale: 0.9) == 10, "Text scale never makes small labels illegible")
expect(abs(TypographyMetrics.pointSize(base: 12, scale: 1.15) - 13.8) < 0.001, "Shared text scaling")
expect(TypographyMetrics.pointSize(base: .nan, scale: .infinity) == 12, "Invalid font preferences are bounded")
print("PASS: typography minimum size, shared scaling and invalid-value safety")

let lockDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("AdaRunLock-\(UUID())")
try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: lockDirectory) }
let lockPath = lockDirectory.appendingPathComponent("instance.lock").path
func checkContention() {
    guard case .acquired(let lock) = AppRunLock.attempt(at: lockPath) else {
        preconditionFailure("The first launch must claim the lock")
    }
    withExtendedLifetime(lock) {
        guard case .occupied(let pid) = AppRunLock.attempt(at: lockPath), pid == getpid() else {
            preconditionFailure("A duplicate must see the owner PID and be denied")
        }
    }
}
checkContention()
checkContention()
print("PASS: exclusive instance lock, owner PID and reclaim after exit")
    }
}
