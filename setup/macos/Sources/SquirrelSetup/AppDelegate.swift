//  AppDelegate.swift
//  Application entry point wiring for the macOS setup program.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

  private var windowController: MainWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = MainWindowController()
    windowController = controller
    controller.show()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
