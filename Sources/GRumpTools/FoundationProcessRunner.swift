import Foundation
import GRumpCore

public struct FoundationProcessRunner: BackgroundProcessRunner {
    public init() {}

    public func run(_ request: ProcessRequest) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
            process.executableURL = URL(fileURLWithPath: request.executable)
            process.arguments = request.arguments
            process.currentDirectoryURL = request.workingDirectory
            if !request.environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(request.environment) { _, new in new }
            }
            process.standardOutput = stdout; process.standardError = stderr
            if request.standardInput != nil { process.standardInput = stdin }
            try process.run()
            if let input = request.standardInput {
                stdin.fileHandleForWriting.write(input)
                try? stdin.fileHandleForWriting.close()
            }
            process.waitUntilExit()
            let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return ProcessResult(exitCode: process.terminationStatus, standardOutput: output, standardError: error)
        }.value
    }

    public func start(_ request: ProcessRequest) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executable)
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectory
        if !request.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(request.environment) { _, new in new }
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }
}
