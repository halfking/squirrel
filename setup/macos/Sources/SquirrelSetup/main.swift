//  main.swift
//  Squirrel 鼠鬚管 安装程序 / Squirrel Setup (macOS)
//
//  A native AppKit wizard that installs the Rime input method engine and
//  deploys this repository's shared user configuration on macOS.
//
//  Usage:
//    SquirrelSetup              open the wizard window
//    SquirrelSetup --auto       run the whole installation headlessly
//

import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--auto") {
  // Headless mode: useful for scripting, CI and verifying a build end to end.
  final class ConsoleSink: InstallerDelegate {
    func installer(_ installer: Installer, didUpdateStep id: String, state: StepState) {
      let title = Steps.all.first { $0.id == id }?.title ?? id
      var detail: String {
        switch state {
        case .pending: return ""
        case .running: return "running"
        case .done(let text): return text
        case .skipped(let text): return "skipped: \(text)"
        case .failed(let text): return "FAILED: \(text)"
        }
      }
      print("[\(state.glyph)] \(title) \(detail)")
      fflush(stdout)
    }

    func installer(_ installer: Installer, didLog line: String, level: LogLevel) {
      let marker: String
      switch level {
      case .info: marker = "›"
      case .ok: marker = "✓"
      case .warn: marker = "!"
      case .error: marker = "✕"
      case .detail: marker = " "
      }
      print("\(marker) \(line)")
      fflush(stdout)
    }

    func installerDidFinish(_ installer: Installer, success: Bool) {
      print(success ? "\n=== 安装完成 / install finished ===" : "\n=== 安装失败 / install failed ===")
      exit(success ? 0 : 1)
    }
  }

  let engine = Installer()
  let sink = ConsoleSink()
  engine.delegate = sink
  engine.start()

  // start() dispatches to a background queue; keep the process alive until done.
  RunLoop.current.run()
} else {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.regular)
  app.activate(ignoringOtherApps: true)
  app.run()
}
