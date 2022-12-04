// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import SwiftUI

@MainActor
final class ApplicationState: ObservableObject {
  @Published private(set) var allKeys: [String] = []

  func refreshKeys() {
    Task {
      allKeys = await FakeFileSystem.shared.allFilenames.sorted()
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
