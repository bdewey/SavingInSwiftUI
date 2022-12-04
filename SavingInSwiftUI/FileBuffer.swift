// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Foundation
import SwiftUI

@MainActor
/// Holds the contents of a file read from ``FakeFileSystem``.
final class FileBuffer: ObservableObject, Identifiable {
  init(filename: String) {
    self.filename = filename
    Task {
      _text = try await FakeFileSystem.shared.loadFile(filename: filename)
      isLoading = false
    }
  }

  /// The file that we read/write from.
  nonisolated let filename: String
  nonisolated var id: String { filename }

  /// If true, this buffer contains changes that have not yet been saved.
  @Published private(set) var isDirty = false

  /// If true, the contents of the buffer have not yet been read from ``FakeFileSystem``
  @Published private(set) var isLoading = true

  /// The actual file contents. The stored property is private and is exposed through the computed property ``text``
  private var _text = ""

  /// Gets/sets the in-memory copy of the file contents.
  ///
  /// Setting the in-memory copy of the file contents sets ``isDirty`` to `true` and makes sure that autosave will run some time in the future.
  var text: String {
    get {
      assert(!isLoading, "Shouldn't read the value of `text` until it is loaded.")
      return _text
    }
    set {
      assert(!isLoading, "Shouldn't write the value of `text` until it is loaded.")
      objectWillChange.send()
      _text = newValue
      isDirty = true
      createAutosaveTaskIfNeeded()
    }
  }

  /// Saves the contents of this buffer to ``FakeFileSystem``
  func save() async throws {
    guard isDirty else { return }

    // Note: I think reversing the order of the next two lines introduces a race condition.
    // Concurrency is still hard, even when everything is @MainActor.
    //
    // The race that is possible IF you do "save then set isDirty = false":
    //
    // 1. Change buffer to "version 1". At this point isDirty = true
    // 2. Call save(). This will *start* the process of saving the string "version 1". This is async, and suspends.
    // 3. While waiting for the i/o to finish, change buffer to "version 2". At this point, isDirty = true
    // 4. The i/o from step 2 finishes, and you set isDirty = false. HOWEVER, the current contents of the buffer ("version 2")
    //    have not been saved. The buffer is dirty, and you won't save "version 2" unless you make more changes later.
    isDirty = false
    do {
      try await FakeFileSystem.shared.saveFile(_text, filename: filename)
    } catch {
      // If there was an error, we need to reset `isDirty`
      isDirty = true
      throw error
    }
  }

  private(set) var autosaveTask: Task<Void, Never>?

  /// Creates an autosave task, if needed.
  ///
  /// The autosave task will save the contents of the buffer at a point in the future.
  /// This lets you batch up saves versus trying to save on each keystroke.
  private func createAutosaveTaskIfNeeded() {
    guard autosaveTask == nil else { return }
    autosaveTask = Task {
      try? await Task.sleep(until: .now + .seconds(5), clock: .continuous)
      try? await save()
      autosaveTask = nil
    }
  }
}
