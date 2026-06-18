import Foundation

/// Canonicalizes filesystem paths so a transcript-recorded cwd and a live process's
/// cwd (from `lsof`) compare equal — both are resolved through symlinks
/// (e.g. `/tmp` → `/private/tmp`) to the same string.
public enum PathNormalizer {
    public static func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
