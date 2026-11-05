import AdaCheckSuite
import Foundation

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--showcase" {
    try await AdaCheckSuite.renderShowcase(to: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
} else {
    try await AdaCheckSuite.runAll()
}
