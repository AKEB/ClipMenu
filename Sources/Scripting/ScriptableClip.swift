import JavaScriptCore
import Foundation

/// The JavaScript-visible bridge object that exposes clipboard content to
/// action scripts.
///
/// Must replicate the JSExport protocol surface from
/// `legacy/Source/ScriptableClip.{h,m}`.
@objc protocol ScriptableClipExports: JSExport {
    // TODO: Phase 2 — declare all exported properties and methods.
    var stringValue: String? { get }
}

@objc final class ScriptableClip: NSObject, ScriptableClipExports {

    // TODO: Phase 2 — back with a ClipEntry and implement the exported interface.

    var stringValue: String? { nil }
}
