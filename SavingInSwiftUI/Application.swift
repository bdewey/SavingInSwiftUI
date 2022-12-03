//  Created by Brian Dewey on 9/11/22.

import SwiftUI

actor FakeFileSystem {
  private let ioDelayDuration = Duration.milliseconds(250)

  enum Error: Swift.Error {
    case fileDoesNotExist
  }

  private var data: [String: String] = [
    "Test 1": "Hello, world.",
    "Test 2": "Lorem Ipsum",
  ]

  var allKeys: some Sequence<String> {
    data.keys
  }

  func loadFile(key: String) async throws -> String {
    try? await Task.sleep(until: .now + ioDelayDuration, clock: .continuous)
    guard let fileData = data[key] else {
      throw Error.fileDoesNotExist
    }
    return fileData
  }

  func saveFile(_ fileData: String, key: String) async throws {
    try? await Task.sleep(until: .now + ioDelayDuration, clock: .continuous)
    print("Saved contents to \(key): \(fileData)")
    data[key] = fileData
  }

  static let shared = FakeFileSystem()

  private init() {}
}

@MainActor
final class FileBuffer: ObservableObject, Identifiable {
  init(key: String) {
    self.key = key
    Task {
      buffer = try await FakeFileSystem.shared.loadFile(key: key)
      isLoading = false
    }
  }

  nonisolated let key: String
  nonisolated var id: String { key }

  @Published var isDirty = false
  @Published var isLoading = true

  private var buffer = ""

  var textBinding: Binding<String> {
    Binding<String> { [weak self] in
      self?.buffer ?? ""
    } set: { [weak self] updatedString in
      guard let self else { return }
      self.buffer = updatedString
      self.isDirty = true
      self.autosaveIfNeeded()
    }
  }

  func save() async throws {
    guard isDirty else { return }
    try await FakeFileSystem.shared.saveFile(buffer, key: key)
    isDirty = false
  }

  private(set) var autosaveTask: Task<(), Never>?

  func autosaveIfNeeded() {
    guard autosaveTask == nil else { return }
    autosaveTask = Task {
      try? await Task.sleep(until: .now + .seconds(5), clock: .continuous)
      try? await save()
      autosaveTask = nil
    }
  }
}

@MainActor
final class ApplicationState: ObservableObject {
  @Published private(set) var allKeys: [String] = []

  func refreshKeys() {
    Task {
      allKeys = await FakeFileSystem.shared.allKeys.sorted()
    }
  }
}

@main
struct Application: App {
  @StateObject private var state = ApplicationState()

  var body: some Scene {
    WindowGroup {
      AllFilesSplitView().environmentObject(state)
    }
  }
}

struct AllFilesSplitView: View {
  @EnvironmentObject private var state: ApplicationState
  @StateObject private var viewModel = ViewModel()

  @MainActor
  private class ViewModel: ObservableObject {
    @Published var activeFile: FileBuffer?

    var activeFileKey: Binding<String?> {
      Binding<String?> { [weak self] in
        self?.activeFile?.key
      } set: { [weak self] newKey in
        guard let self, self.activeFile?.key != newKey else { return }
        self.activeFile = newKey.flatMap { FileBuffer(key: $0) }
      }
    }
  }

  var body: some View {
    NavigationSplitView {
      List(state.allKeys, id: \.self, selection: viewModel.activeFileKey) { key in
        Text(key)
      }
    } detail: {
      if let buffer = viewModel.activeFile {
        FileEditor(buffer: buffer)
          .onDisappear {
            Task {
              try? await buffer.save()
            }
          }
          .id(buffer.key)
      }
    }
    .task {
      state.refreshKeys()
    }
  }
}

struct FileEditor: View {
  @ObservedObject var buffer: FileBuffer

  var body: some View {
    if buffer.isLoading {
      ProgressView()
    } else {
      TextEditor(text: buffer.textBinding).padding()
    }
  }
}
