//
//  AllFilesSplitView.swift
//  SavingInSwiftUI
//
//  Created by Brian Dewey on 12/4/22.
//

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

    /// A Binding to the filename we are currently editing.
    ///
    /// If you change the filename, this will create a new `activeFile` instance for the new file.
    var activeFilename: Binding<String?> {
      Binding<String?> { [weak self] in
        self?.activeFile?.filename
      } set: { [weak self] newKey in
        guard let self, self.activeFile?.filename != newKey else { return }
        self.activeFile = newKey.flatMap { FileBuffer(filename: $0) }
      }
    }
  }

  var body: some View {
    NavigationSplitView {
      List(state.allKeys, id: \.self, selection: viewModel.activeFilename) { key in
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
          .id(buffer.filename)
      }
    }
    .task {
      state.refreshKeys()
    }
  }
}

