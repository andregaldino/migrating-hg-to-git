use std::path::Path;

pub fn get_path_from_bytes(bytes: &[u8]) -> &Path {
    let os_str;
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        os_str = std::ffi::OsStr::from_bytes(bytes);
    }
    #[cfg(windows)]
    {
        // TODO: convert from Windows MBCS (ANSI encoding) to WTF8.
        // Perhaps, the return type would have to be Result<PathBuf>.
        use std::os::windows::ffi::OsStrExt;
        os_str = std::ffi::OsString::from_wide(bytes);
    }

    Path::new(os_str)
}
