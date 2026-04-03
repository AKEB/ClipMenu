import SwiftData

/// CRUD operations over SnippetFolder / Snippet records.
///
/// Reference: `legacy/Source/SnippetsController.{h,m}`.
actor SnippetService {

    private var context: ModelContext?

    func start(context: ModelContext) {
        self.context = context
    }

    // TODO: Phase 1 — implement create/read/update/delete for folders and snippets,
    //       replicating sort-order logic from SnippetsController.m.

    func paste(snippet: Snippet) async {
        // TODO: Phase 2 — write snippet.content to NSPasteboard then call PasteService.paste().
    }
}
