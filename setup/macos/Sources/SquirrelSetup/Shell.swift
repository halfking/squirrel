//  Shell.swift
//  Process helpers for the Squirrel setup program.
//
//  Created for the cross-platform Squirrel setup GUI (macOS / Windows / Linux).
//

import Foundation

enum ShellError: Error, LocalizedError {
  case launchFailed(String)
  case nonZeroExit(Int32, String)
  case emptyOutput

  var errorDescription: String? {
    switch self {
    case .launchFailed(let cmd): return "无法启动命令 / cannot launch: \(cmd)"
    case .nonZeroExit(let code, let out): return "命令退出码 \(code) / command exited \(code)\n\(out)"
    case .emptyOutput: return "命令没有输出 / command produced no output"
    }
  }
}

enum Shell {

  /// Run a command, stream stdout+stderr into `onOutput`, and return collected output.
  @discardableResult
  static func run(_ launchPath: String,
                  _ arguments: [String],
                  workingDirectory: String? = nil,
                  environment: [String: String]? = nil,
                  onOutput: ((String) -> Void)? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    if let workingDirectory {
      process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    }
    if let environment {
      process.environment = environment
    }

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
    } catch {
      throw ShellError.launchFailed("\(launchPath) \(arguments.joined(separator: " "))")
    }

    var collected = ""
    let queue = DispatchQueue(label: "shell.reader")
    let handle = pipe.fileHandleForReading
    queue.async {
      let data = handle.readDataToEndOfFile()
      if let text = String(data: data, encoding: .utf8), !text.isEmpty {
        collected = text
        onOutput?(text)
      }
    }

    process.waitUntilExit()
    queue.sync {}

    if process.terminationStatus != 0 {
      throw ShellError.nonZeroExit(process.terminationStatus, collected.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return collected
  }

  /// Run a shell snippet without elevation.
  @discardableResult
  static func sh(_ script: String,
                 onOutput: ((String) -> Void)? = nil) throws -> String {
    try run("/bin/sh", ["-c", script], onOutput: onOutput)
  }

  /// Run a shell snippet through the macOS authorization dialog.
  ///
  /// The script is written to a temporary file so that no quoting is needed on the
  /// AppleScript side, and `do shell script ... with administrator privileges`
  /// performs the standard user/password or Touch ID prompt.
  @discardableResult
  static func shPrivileged(_ script: String, onOutput: ((String) -> Void)? = nil) throws -> String {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("squirrel-setup-\(UUID().uuidString).sh")
    try script.write(to: tmp, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let tmpPath = tmp.path.replacingOccurrences(of: "\"", with: "\\\"")
    let appleScript = "do shell script \"/bin/sh \(tmpPath)\" with administrator privileges"
    return try run("/usr/bin/osascript", ["-e", appleScript], onOutput: onOutput)
  }

  /// Whether the given executable can be found on `PATH`.
  static func which(_ tool: String) -> String? {
    guard let out = try? sh("command -v \(tool) 2>/dev/null") else { return nil }
    let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
  }

  /// Whether the current process is running as root.
  static var isRoot: Bool { geteuid() == 0 }
}
