//  Steps.swift
//  Step model shared by the UI and the installer engine.
//

import Foundation

enum StepState: Equatable {
  case pending
  case running
  case done(String)      // finished, with a short detail line
  case skipped(String)   // nothing to do on this machine
  case failed(String)    // error summary

  var glyph: String {
    switch self {
    case .pending: return "○"
    case .running: return "◐"
    case .done: return "✓"
    case .skipped: return "⊘"
    case .failed: return "✕"
    }
  }

  var isFinished: Bool {
    switch self {
    case .done, .skipped, .failed: return true
    case .pending, .running: return false
    }
  }
}

struct Step {
  let id: String
  let title: String
  let subtitle: String
  /// Whether this step needs administrator rights.
  let needsAdmin: Bool

  init(_ id: String, _ title: String, _ subtitle: String, needsAdmin: Bool = false) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.needsAdmin = needsAdmin
  }
}

enum Steps {
  static let all: [Step] = [
    Step("detect", "检测运行环境", "识别系统版本、已安装的 Rime 与用户配置"),
    Step("engine", "安装 Squirrel 鼠鬚管", "安装输入法引擎到 /Library/Input Methods", needsAdmin: true),
    Step("config", "写入用户配置", "部署 default.custom.yaml 与升级版五笔·拼音方案（混输 / 英文候选 / 左 Shift 切换）"),
    Step("presets", "安装词库与方案", "按 plum 方案下载 wubi86、朙月拼音、Easy English 词库"),
    Step("deploy", "编译并启用输入法", "运行 Squirrel --build 并注册、启用输入源"),
    Step("done", "完成", "打开配置目录或开始使用")
  ]

  static func index(of id: String) -> Int? { all.firstIndex { $0.id == id } }
}
