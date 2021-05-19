/// Added at the start of `.hg/dirstate` when the "v2" format is used.
/// Acts like a "magic number". This is a sanity check, not strictly necessary
/// since `.hg/requires` already governs which format should be used.
pub const V2_FORMAT_MARKER: &[u8; 12] = b"dirstate-v2\n";
