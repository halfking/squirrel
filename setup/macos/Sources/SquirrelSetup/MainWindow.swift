//  MainWindow.swift
//  The setup wizard window.
//

import AppKit

final class MainWindowController: NSObject, NSWindowDelegate, InstallerDelegate {

  private let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
  )

  private let installer = Installer()

  // Header
  private let titleLabel = NSTextField(labelWithString: "Squirrel 鼠鬚管 安装程序")
  private let subtitleLabel = NSTextField(labelWithString:
    "为 macOS / Windows / Linux 提供同一套 Rime 配置 · 版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")

  // Step list
  private let stepStack = NSStackView()
  private var statusLabels: [String: NSTextField] = [:]
  private var detailLabels: [String: NSTextField] = [:]
  private var titleLabels: [String: NSTextField] = [:]

  // Log
  private let logView = NSTextView()
  private let progress = NSProgressIndicator()

  // Buttons
  private let installButton = NSButton()
  private let detectButton = NSButton()
  private let revealButton = NSButton()
  private let quitButton = NSButton()
  private let statusLine = NSTextField(labelWithString: "")

  override init() {
    super.init()
    buildUI()
    installer.delegate = self
    installer.detectOnly()
  }

  // MARK: UI construction

  private func buildUI() {
    window.title = "Squirrel 鼠鬚管 安装程序"
    window.delegate = self
    window.minSize = NSSize(width: 780, height: 560)
    window.center()

    titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    subtitleLabel.font = .systemFont(ofSize: 12)
    subtitleLabel.textColor = .secondaryLabelColor

    // Step rows
    stepStack.orientation = .vertical
    stepStack.alignment = .leading
    stepStack.spacing = 2
    for step in Steps.all {
      let row = NSStackView()
      row.orientation = .horizontal
      row.alignment = .firstBaseline
      row.spacing = 10

      let status = NSTextField(labelWithString: "○")
      status.font = .systemFont(ofSize: 15, weight: .medium)
      status.textColor = .tertiaryLabelColor
      status.alignment = .center
      status.widthAnchor.constraint(equalToConstant: 20).isActive = true

      let title = NSTextField(labelWithString: step.title)
      title.font = .systemFont(ofSize: 14, weight: .medium)
      title.widthAnchor.constraint(equalToConstant: 190).isActive = true

      let sub = NSTextField(labelWithString: step.subtitle)
      sub.font = .systemFont(ofSize: 12)
      sub.textColor = .secondaryLabelColor
      sub.lineBreakMode = .byTruncatingTail
      sub.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

      let detail = NSTextField(labelWithString: "")
      detail.font = .systemFont(ofSize: 12)
      detail.textColor = .tertiaryLabelColor
      detail.alignment = .right
      detail.lineBreakMode = .byTruncatingTail
      detail.widthAnchor.constraint(equalToConstant: 190).isActive = true

      row.addArrangedSubview(status)
      row.addArrangedSubview(title)
      row.addArrangedSubview(sub)
      row.addArrangedSubview(detail)
      stepStack.addArrangedSubview(row)

      statusLabels[step.id] = status
      titleLabels[step.id] = title
      detailLabels[step.id] = detail
    }

    // Log view
    let logScroll = NSScrollView()
    logScroll.hasVerticalScroller = true
    logScroll.hasHorizontalScroller = false
    logScroll.autohidesScrollers = true
    logScroll.borderType = .bezelBorder
    logView.isEditable = false
    logView.isSelectable = true
    logView.isRichText = true
    logView.drawsBackground = true
    logView.backgroundColor = .textBackgroundColor
    logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    logView.textContainerInset = NSSize(width: 6, height: 6)
    logView.isVerticallyResizable = true
    logView.isHorizontallyResizable = false
    logView.autoresizingMask = [.width]
    logView.minSize = NSSize(width: 0, height: 0)
    logView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    logView.textContainer?.widthTracksTextView = true
    logView.frame = NSRect(x: 0, y: 0, width: 700, height: 240)
    logScroll.documentView = logView
    let logBox = NSBox()
    logBox.title = "安装日志 / Log"
    logBox.titlePosition = .atTop
    logBox.contentView = logScroll

    // Buttons
    style(installButton, title: "开始安装", prominent: true)
    installButton.target = self
    installButton.action = #selector(startInstall)
    style(detectButton, title: "重新检测", prominent: false)
    detectButton.target = self
    detectButton.action = #selector(reDetect)
    style(revealButton, title: "打开配置目录", prominent: false)
    revealButton.target = self
    revealButton.action = #selector(revealConfigDir)
    style(quitButton, title: "退出", prominent: false)
    quitButton.target = self
    quitButton.action = #selector(quit)

    let buttonRow = NSStackView(views: [installButton, detectButton, revealButton, NSView(), quitButton])
    buttonRow.orientation = .horizontal
    buttonRow.spacing = 10

    statusLine.font = .systemFont(ofSize: 12)
    statusLine.textColor = .secondaryLabelColor

    progress.style = .bar
    progress.isIndeterminate = false
    progress.minValue = 0
    progress.maxValue = Double(Steps.all.count)
    progress.doubleValue = 0

    // Layout
    let header = NSStackView(views: [titleLabel, subtitleLabel])
    header.orientation = .vertical
    header.alignment = .leading
    header.spacing = 4

    let content = NSStackView(views: [header, stepStack, progress, logBox, statusLine, buttonRow])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 12
    content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
    content.translatesAutoresizingMaskIntoConstraints = false

    stepStack.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40).isActive = true
    logBox.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40).isActive = true

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 620))
    window.contentView = container
    container.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      content.topAnchor.constraint(equalTo: container.topAnchor),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
    content.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -40).isActive = true
    logBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func style(_ button: NSButton, title: String, prominent: Bool) {
    button.title = title
    button.bezelStyle = prominent ? .rounded : .rounded
    button.controlSize = .regular
    button.font = .systemFont(ofSize: 13, weight: prominent ? .semibold : .regular)
  }

  // MARK: Actions

  @objc private func startInstall() {
    guard !installer.isRunning else { return }
    setRunning(true)
    installer.start()
  }

  @objc private func reDetect() {
    guard !installer.isRunning else { return }
    logView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    installer.detectOnly()
  }

  @objc private func revealConfigDir() {
    let dir = URL(fileURLWithPath: Installer.Path.userRimeDir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    NSWorkspace.shared.open(dir)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func setRunning(_ running: Bool) {
    installButton.isEnabled = !running
    detectButton.isEnabled = !running
    progress.isHidden = !running
    statusLine.stringValue = running ? "正在安装，请勿关闭窗口…" : ""
  }

  // MARK: InstallerDelegate

  func installer(_ installer: Installer, didUpdateStep id: String, state: StepState) {
    guard let status = statusLabels[id], let detail = detailLabels[id] else { return }
    status.stringValue = state.glyph
    switch state {
    case .pending:
      status.textColor = .tertiaryLabelColor
      detail.stringValue = ""
      titleLabels[id]?.textColor = .labelColor
    case .running:
      status.textColor = .systemOrange
      detail.stringValue = "进行中…"
      titleLabels[id]?.textColor = .labelColor
    case .done(let text):
      status.textColor = .systemGreen
      detail.stringValue = text
    case .skipped(let text):
      status.textColor = .systemGray
      detail.stringValue = text
    case .failed(let text):
      status.textColor = .systemRed
      detail.stringValue = text
    }
    if let index = Steps.index(of: id), state.isFinished {
      progress.doubleValue = Double(index + 1)
    }
  }

  func installer(_ installer: Installer, didLog line: String, level: LogLevel) {
    let color: NSColor
    let prefix: String
    switch level {
    case .info: color = .labelColor; prefix = "›"
    case .ok: color = .systemGreen; prefix = "✓"
    case .warn: color = .systemOrange; prefix = "!"
    case .error: color = .systemRed; prefix = "✕"
    case .detail: color = .secondaryLabelColor; prefix = " "
    }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
      .foregroundColor: color
    ]
    let text = "\(prefix) \(line)\n"
    let attributed = NSAttributedString(string: text, attributes: attributes)
    guard let storage = logView.textStorage else { return }
    if storage.length == 0 {
      storage.setAttributedString(attributed)
    } else {
      storage.append(attributed)
    }
    logView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
  }

  func installerDidFinish(_ installer: Installer, success: Bool) {
    setRunning(false)
    statusLine.stringValue = success
      ? "安装完成 ✅ 请在「系统设置 › 键盘 › 输入法」中确认已勾选 Squirrel。"
      : "安装未完成，请根据日志排查后点击「开始安装」重试。"
    statusLine.textColor = success ? .systemGreen : .systemRed
    revealButton.needsDisplay = true
  }

  // MARK: NSWindowDelegate

  func windowWillClose(_ notification: Notification) {
    NSApp.terminate(nil)
  }
}
