// dirs_multiset.rs
//
// Copyright 2019 Raphaël Gomès <rgomes@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

//! A multiset of directory names.
//!
//! Used to counts the references to directories in a manifest or dirstate.
use crate::utils::hg_path::{HgPath, HgPathBuf};
use crate::{
    dirstate::EntryState, utils::files, DirstateEntry, DirstateMapError,
};
use std::collections::hash_map::{self, Entry};
use std::collections::HashMap;

// could be encapsulated if we care API stability more seriously
pub type DirsMultisetIter<'a> = hash_map::Keys<'a, HgPathBuf, u32>;

#[derive(PartialEq, Debug)]
pub struct DirsMultiset {
    inner: HashMap<HgPathBuf, u32>,
}

impl DirsMultiset {
    /// Initializes the multiset from a dirstate.
    ///
    /// If `skip_state` is provided, skips dirstate entries with equal state.
    pub fn from_dirstate(
        vec: &HashMap<HgPathBuf, DirstateEntry>,
        skip_state: Option<EntryState>,
    ) -> Self {
        let mut multiset = DirsMultiset {
            inner: HashMap::new(),
        };

        for (filename, DirstateEntry { state, .. }) in vec {
            // This `if` is optimized out of the loop
            if let Some(skip) = skip_state {
                if skip != *state {
                    multiset.add_path(filename);
                }
            } else {
                multiset.add_path(filename);
            }
        }

        multiset
    }

    /// Initializes the multiset from a manifest.
    pub fn from_manifest(vec: &Vec<HgPathBuf>) -> Self {
        let mut multiset = DirsMultiset {
            inner: HashMap::new(),
        };

        for filename in vec {
            multiset.add_path(filename);
        }

        multiset
    }

    /// Increases the count of deepest directory contained in the path.
    ///
    /// If the directory is not yet in the map, adds its parents.
    pub fn add_path(&mut self, path: &HgPath) {
        for subpath in files::find_dirs(path) {
            if let Some(val) = self.inner.get_mut(subpath) {
                *val += 1;
                break;
            }
            self.inner.insert(subpath.to_owned(), 1);
        }
    }

    /// Decreases the count of deepest directory contained in the path.
    ///
    /// If it is the only reference, decreases all parents until one is
    /// removed.
    /// If the directory is not in the map, something horrible has happened.
    pub fn delete_path(
        &mut self,
        path: &HgPath,
    ) -> Result<(), DirstateMapError> {
        for subpath in files::find_dirs(path) {
            match self.inner.entry(subpath.to_owned()) {
                Entry::Occupied(mut entry) => {
                    let val = entry.get().clone();
                    if val > 1 {
                        entry.insert(val - 1);
                        break;
                    }
                    entry.remove();
                }
                Entry::Vacant(_) => {
                    return Err(DirstateMapError::PathNotFound(
                        path.to_owned(),
                    ))
                }
            };
        }

        Ok(())
    }

    pub fn contains(&self, key: &HgPath) -> bool {
        self.inner.contains_key(key)
    }

    pub fn iter(&self) -> DirsMultisetIter {
        self.inner.keys()
    }

    pub fn len(&self) -> usize {
        self.inner.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn test_delete_path_path_not_found() {
        let mut map = DirsMultiset::from_manifest(&vec![]);
        let path = HgPathBuf::from_bytes(b"doesnotexist/");
        assert_eq!(
            Err(DirstateMapError::PathNotFound(path.to_owned())),
            map.delete_path(&path)
        );
    }

    #[test]
    fn test_delete_path_empty_path() {
        let mut map = DirsMultiset::from_manifest(&vec![HgPathBuf::new()]);
        let path = HgPath::new(b"");
        assert_eq!(Ok(()), map.delete_path(path));
        assert_eq!(
            Err(DirstateMapError::PathNotFound(path.to_owned())),
            map.delete_path(path)
        );
    }

    #[test]
    fn test_delete_path_successful() {
        let mut map = DirsMultiset {
            inner: [("", 5), ("a", 3), ("a/b", 2), ("a/c", 1)]
                .iter()
                .map(|(k, v)| (HgPathBuf::from_bytes(k.as_bytes()), *v))
                .collect(),
        };

        assert_eq!(Ok(()), map.delete_path(HgPath::new(b"a/b/")));
        eprintln!("{:?}", map);
        assert_eq!(Ok(()), map.delete_path(HgPath::new(b"a/b/")));
        eprintln!("{:?}", map);
        assert_eq!(
            Err(DirstateMapError::PathNotFound(HgPathBuf::from_bytes(
                b"a/b/"
            ))),
            map.delete_path(HgPath::new(b"a/b/"))
        );

        assert_eq!(2, *map.inner.get(HgPath::new(b"a")).unwrap());
        assert_eq!(1, *map.inner.get(HgPath::new(b"a/c")).unwrap());
        eprintln!("{:?}", map);
        assert_eq!(Ok(()), map.delete_path(HgPath::new(b"a/")));
        eprintln!("{:?}", map);

        assert_eq!(Ok(()), map.delete_path(HgPath::new(b"a/c/")));
        assert_eq!(
            Err(DirstateMapError::PathNotFound(HgPathBuf::from_bytes(
                b"a/c/"
            ))),
            map.delete_path(HgPath::new(b"a/c/"))
        );
    }

    #[test]
    fn test_add_path_empty_path() {
        let mut map = DirsMultiset::from_manifest(&vec![]);
        let path = HgPath::new(b"");
        map.add_path(path);

        assert_eq!(1, map.len());
    }

    #[test]
    fn test_add_path_successful() {
        let mut map = DirsMultiset::from_manifest(&vec![]);

        map.add_path(HgPath::new(b"a/"));
        assert_eq!(1, *map.inner.get(HgPath::new(b"a")).unwrap());
        assert_eq!(1, *map.inner.get(HgPath::new(b"")).unwrap());
        assert_eq!(2, map.len());

        // Non directory should be ignored
        map.add_path(HgPath::new(b"a"));
        assert_eq!(1, *map.inner.get(HgPath::new(b"a")).unwrap());
        assert_eq!(2, map.len());

        // Non directory will still add its base
        map.add_path(HgPath::new(b"a/b"));
        assert_eq!(2, *map.inner.get(HgPath::new(b"a")).unwrap());
        assert_eq!(2, map.len());

        // Duplicate path works
        map.add_path(HgPath::new(b"a/"));
        assert_eq!(3, *map.inner.get(HgPath::new(b"a")).unwrap());

        // Nested dir adds to its base
        map.add_path(HgPath::new(b"a/b/"));
        assert_eq!(4, *map.inner.get(HgPath::new(b"a")).unwrap());
        assert_eq!(1, *map.inner.get(HgPath::new(b"a/b")).unwrap());

        // but not its base's base, because it already existed
        map.add_path(HgPath::new(b"a/b/c/"));
        assert_eq!(4, *map.inner.get(HgPath::new(b"a")).unwrap());
        assert_eq!(2, *map.inner.get(HgPath::new(b"a/b")).unwrap());

        map.add_path(HgPath::new(b"a/c/"));
        assert_eq!(1, *map.inner.get(HgPath::new(b"a/c")).unwrap());

        let expected = DirsMultiset {
            inner: [("", 2), ("a", 5), ("a/b", 2), ("a/b/c", 1), ("a/c", 1)]
                .iter()
                .map(|(k, v)| (HgPathBuf::from_bytes(k.as_bytes()), *v))
                .collect(),
        };
        assert_eq!(map, expected);
    }

    #[test]
    fn test_dirsmultiset_new_empty() {
        let new = DirsMultiset::from_manifest(&vec![]);
        let expected = DirsMultiset {
            inner: HashMap::new(),
        };
        assert_eq!(expected, new);

        let new = DirsMultiset::from_dirstate(&HashMap::new(), None);
        let expected = DirsMultiset {
            inner: HashMap::new(),
        };
        assert_eq!(expected, new);
    }

    #[test]
    fn test_dirsmultiset_new_no_skip() {
        let input_vec = ["a/", "b/", "a/c", "a/d/"]
            .iter()
            .map(|e| HgPathBuf::from_bytes(e.as_bytes()))
            .collect();
        let expected_inner = [("", 2), ("a", 3), ("b", 1), ("a/d", 1)]
            .iter()
            .map(|(k, v)| (HgPathBuf::from_bytes(k.as_bytes()), *v))
            .collect();

        let new = DirsMultiset::from_manifest(&input_vec);
        let expected = DirsMultiset {
            inner: expected_inner,
        };
        assert_eq!(expected, new);

        let input_map = ["a/", "b/", "a/c", "a/d/"]
            .iter()
            .map(|f| {
                (
                    HgPathBuf::from_bytes(f.as_bytes()),
                    DirstateEntry {
                        state: EntryState::Normal,
                        mode: 0,
                        mtime: 0,
                        size: 0,
                    },
                )
            })
            .collect();
        let expected_inner = [("", 2), ("a", 3), ("b", 1), ("a/d", 1)]
            .iter()
            .map(|(k, v)| (HgPathBuf::from_bytes(k.as_bytes()), *v))
            .collect();

        let new = DirsMultiset::from_dirstate(&input_map, None);
        let expected = DirsMultiset {
            inner: expected_inner,
        };
        assert_eq!(expected, new);
    }

    #[test]
    fn test_dirsmultiset_new_skip() {
        let input_map = [
            ("a/", EntryState::Normal),
            ("a/b/", EntryState::Normal),
            ("a/c", EntryState::Removed),
            ("a/d/", EntryState::Merged),
        ]
        .iter()
        .map(|(f, state)| {
            (
                HgPathBuf::from_bytes(f.as_bytes()),
                DirstateEntry {
                    state: *state,
                    mode: 0,
                    mtime: 0,
                    size: 0,
                },
            )
        })
        .collect();

        // "a" incremented with "a/c" and "a/d/"
        let expected_inner = [("", 1), ("a", 2), ("a/d", 1)]
            .iter()
            .map(|(k, v)| (HgPathBuf::from_bytes(k.as_bytes()), *v))
            .collect();

        let new =
            DirsMultiset::from_dirstate(&input_map, Some(EntryState::Normal));
        let expected = DirsMultiset {
            inner: expected_inner,
        };
        assert_eq!(expected, new);
    }
}
