//  Installer.swift
//  The five-step installation engine.
//

import AppKit
import Foundation

enum LogLevel {
  case info, ok, warn, error, detail
}

protocol InstallerDelegate: AnyObject {
  func installer(_ installer: Installer, didUpdateStep id: String, state: StepState)
  func installer(_ installer: Installer, didLog line: String, level: LogLevel)
  func installerDidFinish(_ installer: Installer, success: Bool)
}

final class Installer {

  // MARK: Paths

  enum Path {
    static var squirrelInstalled: String { "/Library/Input Methods/Squirrel.app" }
    static var squirrelBinary: String { squirrelInstalled + "/Contents/MacOS/Squirrel" }
    static var userRimeDir: String {
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Rime", isDirectory: true).path
    }
  }

  // MARK: State

  private(set) var states: [String: StepState] = [:]
  private(set) var isRunning = false
  weak var delegate: InstallerDelegate?

  private let queue = DispatchQueue(label: "squirrel.setup.installer")
  private var squirrelPath: String = Path.squirrelInstalled
  private var summary: [String] = []

  init() {
    for step in Steps.all { states[step.id] = .pending }
  }

  // MARK: Public API

  func start() {
    queue.async { [weak self] in
      guard let self, !self.isRunning else { return }
      self.isRunning = true
      self.summary = []
      DispatchQueue.main.async { self.setAllPending() }

      var success = true
      do {
        try self.runDetect()
        try self.runEngine()
        try self.runConfig()
        try self.runPresets()
        try self.runDeploy()
      } catch {
        self.log("\(error.localizedDescription)", .error)
        success = false
      }

      if success {
        self.finish(.done(""))
        self.log("全部完成，可以开始使用了。", .ok)
      } else {
        self.finish(.failed("请查看上方日志后重试"))
      }
      self.isRunning = false
      DispatchQueue.main.async {
        self.delegate?.installerDidFinish(self, success: success)
      }
    }
  }

  /// Run detection only, to fill in the environment summary.
  func detectOnly() {
    queue.async { [weak self] in
      guard let self else { return }
      do {
        try self.runDetect()
      } catch {
        self.log("\(error.localizedDescription)", .error)
      }
    }
  }

  // MARK: Step 1 — detect

  private func runDetect() throws {
    currentStepID = "detect"
    set(.running)
    log("── 1/5 检测运行环境 / Detecting environment", .info)

    let os = ProcessInfo.processInfo.operatingSystemVersion
    let versionString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    log("macOS \(versionString) · \(currentArch()) · 用户 \(NSUserName())", .detail)

    if FileManager.default.fileExists(atPath: Path.squirrelInstalled) {
      let version = squirrelVersion(at: Path.squirrelInstalled) ?? "未知版本"
      log("已安装 Squirrel：\(Path.squirrelInstalled) (\(version))", .ok)
      squirrelPath = Path.squirrelInstalled
    } else if FileManager.default.fileExists(atPath: Path.squirrelBinary) {
      log("检测到 Squirrel 可执行文件：\(Path.squirrelBinary)", .ok)
    } else {
      log("未检测到 Squirrel 鼠鬚管，将从安装包内置版本安装。", .warn)
    }

    if FileManager.default.fileExists(atPath: Path.userRimeDir) {
      let entries = (try? FileManager.default.contentsOfDirectory(atPath: Path.userRimeDir)) ?? []
      log("Rime 用户目录：\(Path.userRimeDir)（\(entries.count) 个文件）", .detail)
      if entries.contains("build") {
        log("已存在编译产物 build/，本次部署会重新编译。", .detail)
      }
    } else {
      log("Rime 用户目录尚未创建：\(Path.userRimeDir)", .detail)
    }

    log("管理员权限：\(Shell.isRoot ? "已获取" : "按需提权（安装引擎时会弹出系统授权框）")", .detail)

    // Reachability probe for the preset mirror.
    if let data = try? Net.get("https://cdn.jsdelivr.net/gh/rime/rime-wubi@master/wubi86.schema.yaml", timeout: 15),
       !data.isEmpty {
      log("网络：可访问 plum 方案镜像（jsDelivr）", .ok)
    } else {
      log("网络：jsDelivr 不可达，运行时将自动尝试其他镜像。", .warn)
    }

    set(.done("macOS \(versionString)"))
  }

  // MARK: Step 2 — engine

  private func runEngine() throws {
    currentStepID = "engine"
    set(.running)
    log("── 2/5 安装 Squirrel 鼠鬚管 / Installing Squirrel", .info)

    let source = Payload.squirrelApp
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw PayloadError.missing("Squirrel.app")
    }
    let payloadVersion = squirrelVersion(at: source.path) ?? "内置版本"
    log("内置 Squirrel.app：\(source.path) (\(payloadVersion), \(dirSize(source.path)))", .detail)

    // "目录存在就跳过"是错的：安装包内置的引擎可能被换过（换了
    // SharedSupport/default.yaml 之类），而版本号没变。此时重装会静默跳过，
    // 新引擎永远装不上——所以要比对负载指纹，不只看目录在不在。
    if FileManager.default.fileExists(atPath: Path.squirrelInstalled) {
      let installedVersion = squirrelVersion(at: Path.squirrelInstalled) ?? "未知版本"
      if engineMatchesPayload(source.path) {
        log("Squirrel 已安装且与安装包负载一致（\(installedVersion)），跳过安装。", .detail)
        set(.skipped("已安装 \(installedVersion)"))
        return
      }
      log("已安装引擎（\(installedVersion)）与安装包负载不一致，将更新引擎。", .info)
    }

    let quotedSource = shellQuote(source.path)
    let quotedTarget = shellQuote(Path.squirrelInstalled)
    let script = """
    set -e
    if [ -e \(quotedTarget) ]; then
      rm -rf \(quotedTarget)
    fi
    mkdir -p "/Library/Input Methods"
    cp -R \(quotedSource) \(quotedTarget)
    chown -R root:wheel \(quotedTarget)
    chmod -R u+rwX,go+rX \(quotedTarget)
    /usr/bin/codesign --force --deep --sign - \(quotedTarget) 2>/dev/null || true
    """

    log("需要管理员权限，正在弹出系统授权框…", .detail)
    _ = try Shell.shPrivileged(script) { output in
      self.log(output.trimmingCharacters(in: .whitespacesAndNewlines), .detail)
    }

    guard FileManager.default.fileExists(atPath: Path.squirrelBinary) else {
      throw ShellError.nonZeroExit(1, "安装后未找到 \(Path.squirrelBinary)")
    }
    squirrelPath = Path.squirrelInstalled
    log("安装完成：\(Path.squirrelInstalled)", .ok)
    set(.done(payloadVersion))
  }

  // MARK: Step 3 — config

  private func runConfig() throws {
    currentStepID = "config"
    set(.running)
    log("── 3/5 写入用户配置 / Writing user config", .info)

    // 部署顺序很关键：先写我们自己的 wubi_pinyin.schema.yaml，presets 一步
    // 「已存在则跳过下载」才不会用上游原版方案覆盖掉升级版（升级版带
    // 五笔/拼音直接混打和英文单词候选；上游版是反查小词库+繁体输出）。
    let files: [(source: URL, name: String, note: String)] = [
      (Payload.defaultCustomYAML, "default.custom.yaml",
       "  方案：五笔·拼音 / 朙月拼音·简体 / 五笔86；中英切换：左 Shift"),
      (Payload.wubiPinyinSchemaYAML, "wubi_pinyin.schema.yaml",
       "  混输升级 + 英文单词候选（Easy English 词库）"),
    ]
    let dir = URL(fileURLWithPath: Path.userRimeDir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    for file in files {
      guard FileManager.default.fileExists(atPath: file.source.path) else {
        throw PayloadError.missing(file.name)
      }
      let dest = dir.appendingPathComponent(file.name)

      let newData = try Data(contentsOf: file.source)
      if let oldData = try? Data(contentsOf: dest), oldData == newData {
        log("\(file.name) 已是最新内容，跳过写入。", .detail)
        continue
      }

      if FileManager.default.fileExists(atPath: dest.path) {
        let backup = dest.deletingPathExtension().appendingPathExtension("yaml.bak-\(timestamp())")
        try? FileManager.default.copyItem(at: dest, to: backup)
        log("已备份原配置 → \(backup.lastPathComponent)", .detail)
      }

      try newData.write(to: dest, options: .atomic)
      log("写入 \(dest.path)", .ok)
      log(file.note, .detail)
    }
    set(.done("用户配置"))
  }

  // MARK: Step 4 — presets

  private func runPresets() throws {
    currentStepID = "presets"
    set(.running)
    log("── 4/5 安装词库与方案（plum 方案）/ Installing plum presets", .info)

    let manifest = try Payload.presets
    let dir = URL(fileURLWithPath: Path.userRimeDir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var written = 0
    var skipped = 0
    var totalBytes = 0

    for package in manifest.packages {
      log("方案包 \(package.name)：\(package.description)", .detail)
      for file in package.files {
        let dest = dir.appendingPathComponent(file)
        if let existing = try? Data(contentsOf: dest), !existing.isEmpty {
          log("  · \(file) 已存在（\(byteString(existing.count))），跳过下载", .detail)
          skipped += 1
          continue
        }
        do {
          let data = try Net.download(repo: package.repo,
                                      mirror: package.mirror,
                                      ref: package.ref,
                                      file: file,
                                      mirrors: manifest.mirrors)
          try data.write(to: dest, options: .atomic)
          totalBytes += data.count
          written += 1
          log("  ✓ \(file) ← \(package.repo)/\(file) (\(byteString(data.count)))", .ok)
        } catch {
          log("  ✕ \(file) 下载失败：\(error.localizedDescription)", .error)
        }
      }
    }

    if written == 0 && skipped == 0 {
      throw NetError.allMirrorsFailed(file: "全部方案文件", reasons: ["没有成功下载任何方案文件"])
    }
    log("方案文件就绪：新写入 \(written) 个，跳过 \(skipped) 个，共 \(byteString(totalBytes))", .ok)
    set(.done("\(written + skipped) 个方案文件"))
  }

  // MARK: Step 5 — deploy

  private func runDeploy() throws {
    currentStepID = "deploy"
    set(.running)
    log("── 5/5 编译并启用输入法 / Building and enabling", .info)

    let binary = squirrelPath + "/Contents/MacOS/Squirrel"
    guard FileManager.default.fileExists(atPath: binary) else {
      throw ShellError.launchFailed("找不到 Squirrel 可执行文件 \(binary)")
    }

    // Compile the user config. Squirrel --build deploys ~/Library/Rime with its
    // own SharedSupport data, exactly like the menu bar "重新部署" command.
    // Run it from SharedSupport: Squirrel's GUI does the same (OpenCC uses
    // relative dictionary paths from there, and librime otherwise drops an
    // installation.yaml into whatever directory we happen to launch from).
    let sharedSupport = squirrelPath + "/Contents/SharedSupport"
    let buildCWD = FileManager.default.fileExists(atPath: sharedSupport) ? sharedSupport : Path.userRimeDir
    log("运行 Squirrel --build（编译词库，通常需要 5–30 秒）…", .detail)
    let buildOutput = try Shell.run(binary, ["--build"], workingDirectory: buildCWD) { output in
      for line in output.split(separator: "\n") where !line.isEmpty {
        self.log(String(line), .detail)
      }
    }
    if !buildOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      log(buildOutput.trimmingCharacters(in: .whitespacesAndNewlines), .detail)
    }

    let buildFile = URL(fileURLWithPath: Path.userRimeDir)
      .appendingPathComponent("build/default.yaml")
    if FileManager.default.fileExists(atPath: buildFile.path) {
      let compiled = (try? String(contentsOf: buildFile, encoding: .utf8)) ?? ""
      // 只查 "commit_code" 子串太弱：任何一个键映射到 commit_code 都会让它通过。
      // 这里逐行确认 Shift_L 真的映射到 commit_code（左 Shift 中英切换）。
      let shiftToggle = compiled.split(separator: "\n").contains { line in
        line.trimmingCharacters(in: .whitespaces) == "Shift_L: commit_code"
      }
      if shiftToggle {
        log("编译产物 build/default.yaml：Shift_L: commit_code（左 Shift 中英切换）✓", .ok)
      } else {
        log("警告：build/default.yaml 中 Shift_L 未映射到 commit_code，请检查 default.custom.yaml 是否生效。", .warn)
      }
      let buildDir = URL(fileURLWithPath: Path.userRimeDir).appendingPathComponent("build")
      let files = (try? FileManager.default.contentsOfDirectory(atPath: buildDir.path)) ?? []
      let dicts = files.filter { $0.hasSuffix(".dict.yaml") || $0.hasSuffix(".table.bin") }
      log("编译产物：\(files.count) 个文件（含 \(dicts.count) 个词典产物）", .detail)
    } else {
      log("警告：未生成 build/default.yaml，部署可能未成功。", .warn)
    }

    // Register and enable the input source for the current user.
    log("注册输入法（--install）…", .detail)
    _ = try Shell.run(binary, ["--install"]) { self.log($0, .detail) }
    log("启用输入源（--enable-input-source）…", .detail)
    _ = try Shell.run(binary, ["--enable-input-source"]) { self.log($0, .detail) }

    if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "im.rime.inputmethod.Squirrel" }) {
      _ = try? Shell.run(binary, ["--reload"]) { self.log($0, .detail) }
      log("已通知运行中的 Squirrel 重新加载配置。", .detail)
    }

    log("Squirrel 已注册并启用。菜单栏出现 🐿 图标即表示安装成功。", .ok)
    set(.done("已启用"))
  }

  // MARK: Helpers

  private func currentArch() -> String {
    #if arch(arm64)
    return "arm64"
    #else
    return "x86_64"
    #endif
  }

  private func squirrelVersion(at appPath: String) -> String? {
    let plist = URL(fileURLWithPath: appPath)
      .appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist) else { return nil }
    guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let plist = object as? [String: Any] else { return nil }
    return (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
  }

  private func dirSize(_ path: String) -> String {
    // shellQuote 已带单引号；外面再加一层会变成 ''path''，路径里的空格
    // （/Library/Input Methods）会被 shell 拆词。
    let output = (try? Shell.sh("du -sh \(shellQuote(path)) 2>/dev/null | awk '{print $1}'"))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    return output
  }

  /// Whether the installed engine already matches what this installer ships.
  ///
  /// A plain "does /Library/Input Methods/Squirrel.app exist" check is wrong: the
  /// payload can change (a new SharedSupport/default.yaml) without any version
  /// bump, and then a re-run silently skips the upgrade so the new engine never
  /// lands. Comparing the version together with the contents of
  /// SharedSupport/default.yaml catches exactly that.
  ///
  /// This deliberately does not fingerprint the whole bundle: ad-hoc codesigning
  /// rewrites the Mach-O images in place, so the installed copy and the payload
  /// differ in file size even when they are the same build, and a size- or
  /// whole-bundle comparison would reinstall the engine on every run.
  private func engineMatchesPayload(_ payload: String) -> Bool {
    let installedVersion = squirrelVersion(at: Path.squirrelInstalled)
    let payloadVersion = squirrelVersion(at: payload)
    // 两边都取不到版本（例如 build-user.sh 拷出的骨架 Info.plist 没有版本号）
    // 时，不能因"版本未知"判为不一致——那会让每次运行都重装引擎、弹一次
    // 管理员授权框。版本只在至少一方可读时才参与比较，其余交给下面的
    // SharedSupport/default.yaml 内容比对。
    if installedVersion != nil || payloadVersion != nil,
       installedVersion != payloadVersion { return false }

    let relative = "Contents/SharedSupport/default.yaml"
    let installedConfig = URL(fileURLWithPath: Path.squirrelInstalled).appendingPathComponent(relative)
    let payloadConfig = URL(fileURLWithPath: payload).appendingPathComponent(relative)
    guard let installedData = try? Data(contentsOf: installedConfig),
          let payloadData = try? Data(contentsOf: payloadConfig) else { return false }
    return installedData == payloadData
  }

  private func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }

  private func shellQuote(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func byteString(_ bytes: Int) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
  }

  private func setAllPending() {
    for step in Steps.all { states[step.id] = .pending }
    for step in Steps.all { delegate?.installer(self, didUpdateStep: step.id, state: .pending) }
  }

  private func set(_ state: StepState, for id: String? = nil) {
    let target = id ?? currentStepID
    states[target] = state
    DispatchQueue.main.async {
      self.delegate?.installer(self, didUpdateStep: target, state: state)
    }
  }

  private var currentStepID: String = "detect"

  private func finish(_ state: StepState) {
    states["done"] = state
    DispatchQueue.main.async {
      self.delegate?.installer(self, didUpdateStep: "done", state: state)
    }
  }

  func log(_ line: String, _ level: LogLevel) {
    DispatchQueue.main.async {
      self.delegate?.installer(self, didLog: line, level: level)
    }
  }
}
