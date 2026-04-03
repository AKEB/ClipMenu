import SwiftData

@Model
final class Snippet {

    var title: String
    var content: String
    var sortIndex: Int

    var folder: SnippetFolder?

    init(title: String, content: String, sortIndex: Int = 0) {
        self.title     = title
        self.content   = content
        self.sortIndex = sortIndex
    }
}
