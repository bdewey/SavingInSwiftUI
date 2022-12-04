//  Created by Brian Dewey on 9/11/22.

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

