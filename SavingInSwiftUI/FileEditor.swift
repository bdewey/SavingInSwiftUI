// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Foundation
import SwiftUI

/// Creates a `TextEditor` that can edit the contents of a ``FileBuffer``.
struct FileEditor: View {
  @ObservedObject var buffer: FileBuffer

  var body: some View {
    Group {
      if buffer.isLoading {
        ProgressView()
      } else {
        TextEditor(text: $buffer.text)
          .font(.body.leading(.loose))
      }
    }
    .navigationTitle((buffer.isDirty ? "• " : "") + buffer.filename)
  }
}
