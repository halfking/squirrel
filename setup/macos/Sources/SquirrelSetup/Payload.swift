//  Payload.swift
//  Access to files bundled inside SquirrelSetup.app.
//

import Foundation

struct PresetPackage: Decodable {
  struct Spec: Decodable {
    let name: String
    let repo: String
    let mirror: String
    let ref: String
    let description: String
    let files: [String]
  }
  let mirrors: [String]
  let packages: [Spec]
}

enum PayloadError: Error, LocalizedError {
  case missing(String)
  case badManifest(String)

  var errorDescription: String? {
    switch self {
    case .missing(let name):
      return "安装包缺少内置文件 / bundled payload missing: \(name)"
    case .badManifest(let reason):
      return "内置清单解析失败 / bad presets manifest: \(reason)"
    }
  }
}

enum Payload {

  static var resourceURL: URL {
    Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
  }

  /// URL of a file inside the app bundle's Resources directory.
  static func resource(_ name: String) throws -> URL {
    let url = resourceURL.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw PayloadError.missing(name)
    }
    return url
  }

  /// The Squirrel.app shipped with this setup program.
  static var squirrelApp: URL { resourceURL.appendingPathComponent("Squirrel.app") }

  /// The shared user patch (`rime-config/default.custom.yaml`).
  static var defaultCustomYAML: URL {
    resourceURL.appendingPathComponent("default.custom.yaml")
  }

  /// plum preset manifest.
  static var presets: PresetPackage {
    get throws {
      let url = try resource("presets.json")
      let data = try Data(contentsOf: url)
      do {
        return try JSONDecoder().decode(PresetPackage.self, from: data)
      } catch {
        throw PayloadError.badManifest("\(error)")
      }
    }
  }
}
