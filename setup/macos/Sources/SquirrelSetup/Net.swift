//  Net.swift
//  Minimal HTTPS downloader with mirror fallback, used to fetch plum presets.
//

import Foundation

enum NetError: Error, LocalizedError {
  case allMirrorsFailed(file: String, reasons: [String])

  var errorDescription: String? {
    switch self {
    case .allMirrorsFailed(let file, let reasons):
      return "下载失败 / download failed: \(file)\n" + reasons.joined(separator: "\n")
    }
  }
}

enum Net {

  /// Download `url` into memory. Mirrors are tried in order.
  static func get(_ urlString: String, timeout: TimeInterval = 120) throws -> Data {
    guard let url = URL(string: urlString) else {
      throw ShellError.launchFailed("bad url \(urlString)")
    }
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.setValue("SquirrelSetup/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error> = .failure(ShellError.emptyOutput)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      if let error {
        result = .failure(error)
        return
      }
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        result = .failure(ShellError.nonZeroExit(Int32(http.statusCode), "HTTP \(http.statusCode)"))
        return
      }
      guard let data, !data.isEmpty else {
        result = .failure(ShellError.emptyOutput)
        return
      }
      result = .success(data)
    }
    task.resume()
    semaphore.wait()
    return try result.get()
  }

  /// Download a file, trying every mirror template until one succeeds.
  ///
  /// - Parameters:
  ///   - mirrors: URL templates containing `{repo}`, `{mirror}`, `{ref}` and `{file}`.
  static func download(repo: String, mirror: String, ref: String, file: String,
                       mirrors: [String],
                       onProgress: ((Int, Int) -> Void)? = nil) throws -> Data {
    var reasons: [String] = []
    for template in mirrors {
      let urlString = template
        .replacingOccurrences(of: "{repo}", with: repo)
        .replacingOccurrences(of: "{mirror}", with: mirror)
        .replacingOccurrences(of: "{ref}", with: ref)
        .replacingOccurrences(of: "{file}", with: file)
      do {
        let data = try get(urlString)
        onProgress?(data.count, data.count)
        return data
      } catch {
        reasons.append("\(urlString) → \(error.localizedDescription)")
      }
    }
    throw NetError.allMirrorsFailed(file: file, reasons: reasons)
  }
}
