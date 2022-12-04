//
//  FakeFileSystem.swift
//  SavingInSwiftUI
//
//  Created by Brian Dewey on 12/4/22.
//

import Foundation

/// This is a simulation of a file system:
///
/// 1. It associates file names with file contents
/// 2. There's a delay when reading or writing, and reading / writing can fail.
actor FakeFileSystem {
  private let delay = Duration.milliseconds(250)

  enum Error: Swift.Error {
    case fileDoesNotExist
  }

  private var data: [String: String] = [
    "Test 1": "Hello, world.",
    "Test 2": "Lorem Ipsum",
  ]

  var allFilenames: some Sequence<String> {
    data.keys
  }

  func loadFile(filename: String) async throws -> String {
    try? await Task.sleep(until: .now + delay, clock: .continuous)
    guard let fileData = data[filename] else {
      throw Error.fileDoesNotExist
    }
    return fileData
  }

  func saveFile(_ fileData: String, filename: String) async throws {
    try? await Task.sleep(until: .now + delay, clock: .continuous)
    print("Saved contents to \(filename): \(fileData)")
    data[filename] = fileData
  }

  static let shared = FakeFileSystem()

  private init() {}
}

