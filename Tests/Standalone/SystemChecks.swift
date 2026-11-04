import AppKit
import Foundation
import Darwin

@main struct SystemChecks {
 @MainActor static func main() {
  func expect(_ value: Bool, _ label: String) { precondition(value, label) }
  let base = CPUTickSample(user: 100, system: 100, idle: 100, nice: 100)
  let next = CPUTickSample(user: 110, system: 110, idle: 160, nice: 120)
  expect(CPUTickSample.utilization(previous: base, current: next) == 0.4, "CPU percentage derives from tick deltas")
  expect(CPUTickSample.utilization(previous: base, current: base) == nil, "No ticks means no invented CPU reading")
  let beforeWrap = CPUTickSample(user: .max - 2, system: 0, idle: .max - 2, nice: 0)
  let afterWrap = CPUTickSample(user: 2, system: 0, idle: 2, nice: 0)
  expect(CPUTickSample.utilization(previous: beforeWrap, current: afterWrap) == 0.5, "Counter wrap is handled")
  let memory = MemorySnapshot.calculate(total: 1000, pageSize: 10, anonymousPages: 50, purgeablePages: 5, wiredPages: 10, compressorPages: 5)
  expect(memory.used == 600 && memory.compressed == 50 && memory.wired == 100, "Compressed is a subset and not added twice")
  let excessPurge = MemorySnapshot.calculate(total: 100, pageSize: 10, anonymousPages: 1, purgeablePages: 5, wiredPages: 20, compressorPages: 0)
  expect(excessPurge.used == 100 && excessPurge.fraction == 1, "RAM underflow and total clamp")
  let monitor = SystemMonitor(startImmediately: false)
  expect(monitor.cpuUsage == nil && !monitor.sampling, "Initial CPU stays unavailable")
  monitor.refresh(forceDisk: true)
  expect(monitor.cpuUsage == nil, "First sample is a baseline")
  Thread.sleep(forTimeInterval: 0.3)
  monitor.refresh()
  expect(monitor.cpuUsage != nil && monitor.cpuUsage! >= 0 && monitor.cpuUsage! <= 1, "Live CPU samples succeed")
  expect(monitor.memory != nil && monitor.memory!.used <= monitor.totalMemory, "Live RAM succeeds")
  expect(monitor.diskTotal != nil && monitor.diskAvailable != nil && monitor.diskAvailable! <= monitor.diskTotal!, "Live disk succeeds")
  expect(monitor.processorCount > 0 && monitor.totalMemory > 0 && !monitor.modelIdentifier.isEmpty, "Public model data succeeds")
  let host = mach_host_self()
  defer { _ = mach_port_deallocate(mach_task_self_, host) }
  var before: mach_port_urefs_t = 0
  var after: mach_port_urefs_t = 0
  let beforeResult = mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &before)
  for _ in 0..<100 { monitor.refresh() }
  let afterResult = mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &after)
  expect(beforeResult == KERN_SUCCESS && afterResult == KERN_SUCCESS && before == after, "Repeated samples do not leak Mach host send-right references")
  monitor.start()
  expect(monitor.sampling && monitor.cpuUsage == nil, "Start refreshes baseline")
  monitor.stop()
  expect(!monitor.sampling, "Stop clears sampling timer")
  print("PASS: CPU tick delta, no data, wrap; RAM subset and clamp; live CPU/RAM/disk; Mach host port ownership; lifecycle")
 }
}
