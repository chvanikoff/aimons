/// Maps a project working directory to a stable monster seed, so the same project
/// always shows the same creature. FNV-1a 64-bit hash of the UTF-8 path.
public enum ProjectIdentity {
    public static func seed(forCWD cwd: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325   // FNV offset basis
        for byte in cwd.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3    // FNV prime
        }
        return hash
    }
}
