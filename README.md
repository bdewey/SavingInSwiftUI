# Loading, Editing, and Saving Files in SwiftUI

This is a sample app that demonstrates one approach to loading, editing, and saving files in SwiftUI. The constraints:

* Loading and saving files are `async` operations.
* I don't want to save on every keystroke. Instead, I want to autosave at periodic intervals.
* However, when I'm done editing a file, I want to save any outstanding changes right away (rather than waiting for the autosave timer).

## FileBuffer

The core code of the approach is the class `FileBuffer`. A `FileBuffer` manages:

* The in-memory copy of the file contents
* A flag `isLoading` that is true if the in-memory copy of the file has not yet been loaded from disk.
* A flag `isDirty` that is true if the in-memory copy of the file contents have changed, and therefore needs to be saved back to disk.
* `FileBuffer` manages autosaving dirty file contents at periodic intervals...
* ...while also exposing a `save()` method that saves the file contents _right now_.

Here are the key parts of `FileBuffer`. First, note its declaration: this is a `@MainActor ObservableObject` because its primary job is to communicate "truth" to UI elements.

```swift
@MainActor
final class FileBuffer: ObservableObject, Identifiable {
  // ...
}
```

Each `FileBuffer` exposes publishes three properties, only one of which (`text`) is settable. The `isDirty` and `isLoading` properties change as side-effects of other operations inside of `FileBuffer`.

```swift
  /// The in-memory copy of the file.
  /// This is a computed property! More details later.
  var text: String { get set }

  /// If true, this buffer contains changes that have not yet been saved.
  @Published private(set) var isDirty = false

  /// If true, the contents of the buffer have not yet been read from disk
  @Published private(set) var isLoading = true
```

When you first create a `FileBuffer`, `isLoading` starts as `true`. Once the contents of the file have been loaded from disk, `isLoading` becomes `false` and remains `false` for the remainder of the lifetime of the `FileBuffer`.

`isDirty` becomes `true` any time you make a change to `text`, and stays `true` until those changes have been saved to disk. 

Speaking of `text`, let's take a look at how that is implemented:

```swift
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
```

Basically, the computed property `text` is responsible for three things:

1. Validity checking: You shouldn't be accessing `text` until the file contents have been loaded.
2. Maintaining `isDirty`: Any time you change `text`, `isDirty` needs to get set to true.
3. Ensuring that autosave will run after changes get made to `text`.

What is the "autosave task"? It's an example of a technique I've been using in my apps that support Swift Structured Concurrency -- to my brain, it's the most natural way to say, "Run a function exactly once at some point in the future." Here's what that code looks like:

```swift
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
```

Here's how it works.

* The private `autosaveTask` property serves as a flag to know if autosave has been scheduled to run in the future. If it's `nil`, then there's no autosave; if it's non-nil, the autosave will run. While I don't take advantage of this here, in this pattern I use a `Task?` instead of a `Bool` for this flag so you can write something like `_ = await autosaveTask?.value` to wait until the current task completes.
* The first thing the autosave task does is sleep for some duration. I picked a fairly long one in this test code to make it easier to see delays.
* After waiting, the task runs `save()` and clears the autosave task.

The final outcome of this work: As you type away in a document, repeatedly setting the `text` property and changing the in-memory copy of the file, the _first_ change will create an autosave task. _Subsequent_ changes within the autosave window will see that the task exists, so won't create a new task. Finally, after the delay, the `FileBuffer` will save its contents to disk. The _next_ change that happens to `text` will create a new autosave task.

`save()` is an interesting method. I got it wrong three times while working on this sample. This was my first attempt:

```swift
  func save() async throws {
    guard isDirty else { return }

    try await FakeFileSystem.shared.saveFile(_text, filename: filename)
    isDirty = false
  }
```

Simple and elegant! If `isDirty` is false, there are no changes to save. Otherwise, save the changes and set `isDirty` to false. It turns out this code is also **buggy**. There is a race condition. Can you see it? (As an aside, I still haven't fully internalized "running code on a single actor does not mean there are no race conditions." I keep making mistakes like this.)

Here's the race condition:

1. Change `text` to some value, like "version 1." This sets `isDirty` to true.
2. Call `save()`. You see `isDirty` is true, so you continue. 
3. You get to the point where you `await saveFile()`, and this operation suspends until the save completes.
4. *(This is the part I always forget can happen.)* While waiting for the operation in Step 3 above to complete, change `text` to some new value, like "version 2." This sets `isDirty` to true.
5. The operation in Step 3 completes, and you resume executing `save()` after the `await` statement, setting `isDirty` to `false`. **This is the bug.** The value of `text` is "version 2", and this hasn't been saved to disk yet, so `isDirty` should be `true`. Since we set it to `false`, we'll never save the string "version 2" to disk (unless something comes along and makes another change).

This was my first attempt to fix the race condition:

```swift
  func save() async throws {
    guard isDirty else { return }

    isDirty = false
    try await FakeFileSystem.shared.saveFile(_text, filename: filename)
  }
```

This code *looks* wrong to me. "Surely," my brain says, "you don't want to set `isDirty` to `false` until you've saved the file?" However, waiting until the save finishes opens the door to the race condition described above. Setting `isDirty = false` *before* saving means that, when the code suspends in the `await` statement, any future changes to `text` will properly set `isDirty` back to `true` and we won't overwrite that when we resume from the `await`. It fixes the race. However, this code creates a new bug. What happens if the `saveFile()` call fails? We've set `isDirty = false`, but we didn't actually save the contents to disk, so `isDirty` should be `true` at the end of the function.

This leads to my third and hopefully final version of this function:

```swift
  func save() async throws {
    guard isDirty else { return }

    isDirty = false
    do {
      try await FakeFileSystem.shared.saveFile(_text, filename: filename)
    } catch {
      // If there was an error, we need to reset `isDirty`
      isDirty = true
      throw error
    }
  }

```

At this point, `FileBuffer` contains enough logic to connect files to `SwiftUI`. Here is an example of how to use a `FileBuffer`:


```swift
/// Creates a `TextEditor` that can edit the contents of a `FileBuffer`
struct FileEditor: View {
  @ObservedObject var buffer: FileBuffer

  var body: some View {
    Group {
      // (1)
      if buffer.isLoading {
        ProgressView()
      } else {
        // (2)
        TextEditor(text: $buffer.text)
          .font(.body.leading(.loose))
      }
    }
    .navigationTitle((buffer.isDirty ? "• " : "") + buffer.filename)
    // (3)
    .onDisappear {
      Task {
        try? await buffer.save()
      }
    }
    // (4)
    .id(buffer.filename)
  }
}
```

A quick guide to understanding this code:

1. Remember to check the `isLoading` property on the buffer so you don't attempt to read or write invalid contents!
2. If you know the buffer has loaded, you can get a binding to the in-memory copy of the file with `$buffer.text`. Making changes through this binding will create an auto-save task that will ensure the changes get written at some later point in time.
3. However, when we are _done_ with this view, we want to save its contents immediately, rather than waiting for the auto-save task to run.
4. If you forget the `.id(buffer.filename)` line, then the `.onDisappear` block might not run! Without this line, switching from one file to another could reuse the same `FileEditor` instance. An instance doesn't "disappear" if it's reused. The `.id(buffer.filename)` causes SwiftUI to treat `FileEditors` for different files as different `View` instances, which means `.onDisappear` will run.

    Incidentally, this is one of those SwiftUI cases where the order of modifiers matters. The code above works. This code doesn't:

    ```swift
    .id(buffer.filename)
    .onDisappear {
      Task {
        try? await buffer.save()
      }
    }
    ```

    This is another one of those things I often get wrong! My mental model is that all of the view modifiers are _setting properties on some object,_ whereas what really happens is each view modifier _creates a new View with with a new property_. In the broken code above, the `.id` modifier creates a new View with the `id` property set, and then the `.onDisappear` modifier creates yet another new View with an `onDisappear` block. **That "onDisappear" view doesn't have an `id` property tied to the filename,** so the "onDisppear" View doesn't actually disappear when the filename changes, so the "onDisappear" block doesn't run. (At least I *think* this is what's happening. I don't know if my SwiftUI mental model is the best.)

I'm not sure this is the *best* way to work with files in SwiftUI, but it works for me. As you can see, there is some surprisingly tricky issues to work through. I hope this writeup helps others who are working on editing files in SwiftUI!

(A sample working SwiftUI app with all of the code referenced here is available at [https://github.com/bdewey/SavingInSwiftUI](https://github.com/bdewey/SavingInSwiftUI).)