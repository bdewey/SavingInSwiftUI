//
//  FileEditor.swift
//  SavingInSwiftUI
//
//  Created by Brian Dewey on 12/4/22.
//

import Foundation
import SwiftUI

/// Creates a `TextEditor` that can edit the contents of a ``FileBuffer``.
struct FileEditor: View {
  @ObservedObject var buffer: FileBuffer

  var body: some View {
    if buffer.isLoading {
      ProgressView()
    } else {
      TextEditor(text: buffer.textBinding)
        .font(.body.leading(.loose))
    }
  }
}
