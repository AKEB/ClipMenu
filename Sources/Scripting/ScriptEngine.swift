import JavaScriptCore
import Foundation

/// Executes JavaScript action scripts inside a `JSContext`.
///
/// The legacy implementation lives in `legacy/Source/JavaScriptSupport.{h,m}`.
/// Replicate its execution environment (global functions, error handling) when
/// implementing Phase 2.
final class ScriptEngine {

    private let context = JSContext()

    // TODO: Phase 2 — inject ScriptableClip as a global JS object,
    //       expose the same helper functions as legacy JavaScriptSupport.m.

    /// Runs `script` and returns the string result, or `nil` on error.
    func run(script: String, clip: ScriptableClip) -> String? {
        // TODO: Phase 2
        return nil
    }
}
