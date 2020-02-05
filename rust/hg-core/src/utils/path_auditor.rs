// path_auditor.rs
//
// Copyright 2020
// Raphaël Gomès <rgomes@octobus.net>,
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use crate::utils::{
    files::lower_clean,
    find_slice_in_slice,
    hg_path::{hg_path_to_path_buf, HgPath, HgPathBuf, HgPathError},
};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// Ensures that a path is valid for use in the repository i.e. does not use
/// any banned components, does not traverse a symlink, etc.
#[derive(Debug, Default)]
pub struct PathAuditor {
    audited: HashSet<HgPathBuf>,
    audited_dirs: HashSet<HgPathBuf>,
    root: PathBuf,
}

impl PathAuditor {
    pub fn new(root: impl AsRef<Path>) -> Self {
        Self {
            root: root.as_ref().to_owned(),
            ..Default::default()
        }
    }
    pub fn audit_path(
        &mut self,
        path: impl AsRef<HgPath>,
    ) -> Result<(), HgPathError> {
        // TODO windows "localpath" normalization
        let path = path.as_ref();
        if path.is_empty() {
            return Ok(());
        }
        // TODO case normalization
        if self.audited.contains(path) {
            return Ok(());
        }
        // AIX ignores "/" at end of path, others raise EISDIR.
        let last_byte = path.as_bytes()[path.len() - 1];
        if last_byte == b'/' || last_byte == b'\\' {
            return Err(HgPathError::EndsWithSlash(path.to_owned()));
        }
        let parts: Vec<_> = path
            .as_bytes()
            .split(|b| std::path::is_separator(*b as char))
            .collect();

        let first_component = lower_clean(parts[0]);
        let first_component = first_component.as_slice();
        if !path.split_drive().0.is_empty()
            || (first_component == b".hg"
                || first_component == b".hg."
                || first_component == b"")
            || parts.iter().any(|c| c == b"..")
        {
            return Err(HgPathError::InsideDotHg(path.to_owned()));
        }

        // Windows shortname aliases
        for part in parts.iter() {
            if part.contains(&b'~') {
                let mut split = part.splitn(1, |b| *b == b'~');
                let first =
                    split.next().unwrap().to_owned().to_ascii_uppercase();
                let last = split.next().unwrap();
                if last.iter().all(u8::is_ascii_digit)
                    && (first == b"HG" || first == b"HG8B6C")
                {
                    return Err(HgPathError::ContainsIllegalComponent(
                        path.to_owned(),
                    ));
                }
            }
        }
        let lower_path = lower_clean(path.as_bytes());
        if find_slice_in_slice(&lower_path, b".hg").is_some() {
            let lower_parts: Vec<_> = path
                .as_bytes()
                .split(|b| std::path::is_separator(*b as char))
                .collect();
            for pattern in [b".hg".to_vec(), b".hg.".to_vec()].iter() {
                if let Some(pos) = lower_parts[1..]
                    .iter()
                    .position(|part| part == &pattern.as_slice())
                {
                    let base = lower_parts[..=pos]
                        .iter()
                        .fold(HgPathBuf::new(), |acc, p| {
                            acc.join(HgPath::new(p))
                        });
                    return Err(HgPathError::IsInsideNestedRepo {
                        path: path.to_owned(),
                        nested_repo: base,
                    });
                }
            }
        }

        let parts = &parts[..parts.len().saturating_sub(1)];

        // We don't want to add "foo/bar/baz" to `audited_dirs` before checking
        // if there's a "foo/.hg" directory. This also means we won't
        // accidentally traverse a symlink into some other filesystem (which
        // is potentially expensive to access).
        for index in 0..parts.len() {
            let prefix = &parts[..index + 1].join(&b'/');
            let prefix = HgPath::new(prefix);
            if self.audited_dirs.contains(prefix) {
                continue;
            }
            self.check_filesystem(&prefix, &path)?;
        }

        self.audited.insert(path.to_owned());

        Ok(())
    }

    pub fn check_filesystem(
        &self,
        prefix: impl AsRef<HgPath>,
        path: impl AsRef<HgPath>,
    ) -> Result<(), HgPathError> {
        let prefix = prefix.as_ref();
        let path = path.as_ref();
        let current_path = self.root.join(
            hg_path_to_path_buf(prefix)
                .map_err(|_| HgPathError::NotFsCompliant(path.to_owned()))?,
        );
        match std::fs::symlink_metadata(&current_path) {
            Err(e) => {
                // EINVAL can be raised as invalid path syntax under win32.
                if e.kind() != std::io::ErrorKind::NotFound
                    && e.kind() != std::io::ErrorKind::InvalidInput
                    && e.raw_os_error() != Some(20)
                {
                    // Rust does not yet have an `ErrorKind` for
                    // `NotADirectory` (errno 20)
                    // It happens if the dirstate contains `foo/bar` and
                    // foo is not a directory
                    return Err(HgPathError::NotFsCompliant(path.to_owned()));
                }
            }
            Ok(meta) => {
                if meta.file_type().is_symlink() {
                    return Err(HgPathError::TraversesSymbolicLink {
                        path: path.to_owned(),
                        symlink: prefix.to_owned(),
                    });
                }
                if meta.file_type().is_dir()
                    && current_path.join(".hg").is_dir()
                {
                    return Err(HgPathError::IsInsideNestedRepo {
                        path: path.to_owned(),
                        nested_repo: prefix.to_owned(),
                    });
                }
            }
        };

        Ok(())
    }

    pub fn check(&mut self, path: impl AsRef<HgPath>) -> bool {
        self.audit_path(path).is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::utils::files::get_path_from_bytes;
    use crate::utils::hg_path::path_to_hg_path_buf;

    #[test]
    fn test_path_auditor() {
        let mut auditor = PathAuditor::new(get_path_from_bytes(b"/tmp"));

        let path = HgPath::new(b".hg/00changelog.i");
        assert_eq!(
            auditor.audit_path(path),
            Err(HgPathError::InsideDotHg(path.to_owned()))
        );
        let path = HgPath::new(b"this/is/nested/.hg/thing.txt");
        assert_eq!(
            auditor.audit_path(path),
            Err(HgPathError::IsInsideNestedRepo {
                path: path.to_owned(),
                nested_repo: HgPathBuf::from_bytes(b"this/is/nested")
            })
        );

        use std::fs::{create_dir, File};
        use tempfile::tempdir;

        let base_dir = tempdir().unwrap();
        let base_dir_path = base_dir.path();
        let a = base_dir_path.join("a");
        let b = base_dir_path.join("b");
        create_dir(&a).unwrap();
        let in_a_path = a.join("in_a");
        File::create(in_a_path).unwrap();

        // TODO make portable
        std::os::unix::fs::symlink(&a, &b).unwrap();

        let buf = b.join("in_a").components().skip(2).collect::<PathBuf>();
        eprintln!("buf: {}", buf.display());
        let path = path_to_hg_path_buf(buf).unwrap();
        assert_eq!(
            auditor.audit_path(&path),
            Err(HgPathError::TraversesSymbolicLink {
                path: path,
                symlink: path_to_hg_path_buf(
                    b.components().skip(2).collect::<PathBuf>()
                )
                .unwrap()
            })
        );
    }
}
