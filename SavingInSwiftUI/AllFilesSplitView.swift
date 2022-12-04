// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Foundation
import SwiftUI

/// Displays a two-column split view. The sidebar has a list of all files, and the detail view is a ``FileEditor`` that allows editing the file contents.
struct AllFilesSplitView: View {
  @EnvironmentObject private var state: ApplicationState
  @StateObject private var viewModel = ViewModel()

  /// A type that holds the state scoped to this view.
  @MainActor
  private class ViewModel: ObservableObject {
    /// This is the file we are actively editing.
    @Published var activeFile: FileBuffer?

    /// The filename of the file we are currently editing.
    ///
    /// If you change this property, it will create a new `activeFile` instance for the new file.
    var activeFilename: String? {
      get {
        activeFile?.filename
      }
      set {
        if activeFile?.filename != newValue {
          activeFile = newValue.flatMap { FileBuffer(filename: $0) }
        }
      }
    }
  }

  var body: some View {
    NavigationSplitView {
      List(state.allKeys, id: \.self, selection: $viewModel.activeFilename) { key in
        Text(key)
      }
    } detail: {
      if let buffer = viewModel.activeFile {
        FileEditor(buffer: buffer)
      }
    }
    .task {
      state.refreshKeys()
    }
  }
}
