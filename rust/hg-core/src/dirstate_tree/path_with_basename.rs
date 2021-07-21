use crate::utils::hg_path::HgPath;
use std::borrow::{Borrow, Cow};

/// Wraps `HgPath` or `HgPathBuf` to make it behave "as" its last path
/// component, a.k.a. its base name (as in Python’s `os.path.basename`), but
/// also allow recovering the full path.
///
/// "Behaving as" means that equality and comparison consider only the base
/// name, and `std::borrow::Borrow` is implemented to return only the base
/// name. This allows using the base name as a map key while still being able
/// to recover the full path, in a single memory allocation.
#[derive(Debug)]
pub struct WithBasename<T> {
    full_path: T,

    /// The position after the last slash separator in `full_path`, or `0`
    /// if there is no slash.
    base_name_start: usize,
}

impl<T> WithBasename<T> {
    pub fn full_path(&self) -> &T {
        &self.full_path
    }
}

fn find_base_name_start(full_path: &HgPath) -> usize {
    if let Some(last_slash_position) =
        full_path.as_bytes().iter().rposition(|&byte| byte == b'/')
    {
        last_slash_position + 1
    } else {
        0
    }
}

impl<T: AsRef<HgPath>> WithBasename<T> {
    pub fn new(full_path: T) -> Self {
        Self {
            base_name_start: find_base_name_start(full_path.as_ref()),
            full_path,
        }
    }

    pub fn from_raw_parts(full_path: T, base_name_start: usize) -> Self {
        debug_assert_eq!(
            base_name_start,
            find_base_name_start(full_path.as_ref())
        );
        Self {
            base_name_start,
            full_path,
        }
    }

    pub fn base_name(&self) -> &HgPath {
        HgPath::new(
            &self.full_path.as_ref().as_bytes()[self.base_name_start..],
        )
    }

    pub fn base_name_start(&self) -> usize {
        self.base_name_start
    }
}

impl<T: AsRef<HgPath>> Borrow<HgPath> for WithBasename<T> {
    fn borrow(&self) -> &HgPath {
        self.base_name()
    }
}

impl<T: AsRef<HgPath>> std::hash::Hash for WithBasename<T> {
    fn hash<H: std::hash::Hasher>(&self, hasher: &mut H) {
        self.base_name().hash(hasher)
    }
}

impl<T: AsRef<HgPath> + PartialEq> PartialEq for WithBasename<T> {
    fn eq(&self, other: &Self) -> bool {
        self.base_name() == other.base_name()
    }
}

impl<T: AsRef<HgPath> + Eq> Eq for WithBasename<T> {}

impl<T: AsRef<HgPath> + PartialOrd> PartialOrd for WithBasename<T> {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        self.base_name().partial_cmp(other.base_name())
    }
}

impl<T: AsRef<HgPath> + Ord> Ord for WithBasename<T> {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.base_name().cmp(other.base_name())
    }
}

impl<'a> WithBasename<&'a HgPath> {
    pub fn to_cow_borrowed(self) -> WithBasename<Cow<'a, HgPath>> {
        WithBasename {
            full_path: Cow::Borrowed(self.full_path),
            base_name_start: self.base_name_start,
        }
    }

    pub fn to_cow_owned<'b>(self) -> WithBasename<Cow<'b, HgPath>> {
        WithBasename {
            full_path: Cow::Owned(self.full_path.to_owned()),
            base_name_start: self.base_name_start,
        }
    }
}

impl<'a> WithBasename<&'a HgPath> {
    /// Returns an iterator of `WithBasename<&HgPath>` for the ancestor
    /// directory paths of the given `path`, as well as `path` itself.
    ///
    /// For example, the full paths of inclusive ancestors of "a/b/c" are "a",
    /// "a/b", and "a/b/c" in that order.
    pub fn inclusive_ancestors_of(
        path: &'a HgPath,
    ) -> impl Iterator<Item = WithBasename<&'a HgPath>> {
        let mut slash_positions =
            path.as_bytes().iter().enumerate().filter_map(|(i, &byte)| {
                if byte == b'/' {
                    Some(i)
                } else {
                    None
                }
            });
        let mut opt_next_component_start = Some(0);
        std::iter::from_fn(move || {
            opt_next_component_start.take().map(|next_component_start| {
                if let Some(slash_pos) = slash_positions.next() {
                    opt_next_component_start = Some(slash_pos + 1);
                    Self {
                        full_path: HgPath::new(&path.as_bytes()[..slash_pos]),
                        base_name_start: next_component_start,
                    }
                } else {
                    // Not setting `opt_next_component_start` here: there will
                    // be no iteration after this one because `.take()` set it
                    // to `None`.
                    Self {
                        full_path: path,
                        base_name_start: next_component_start,
                    }
                }
            })
        })
    }
}

#[test]
fn test() {
    let a = WithBasename::new(HgPath::new("a").to_owned());
    assert_eq!(&**a.full_path(), HgPath::new(b"a"));
    assert_eq!(a.base_name(), HgPath::new(b"a"));

    let cba = WithBasename::new(HgPath::new("c/b/a").to_owned());
    assert_eq!(&**cba.full_path(), HgPath::new(b"c/b/a"));
    assert_eq!(cba.base_name(), HgPath::new(b"a"));

    assert_eq!(a, cba);
    let borrowed: &HgPath = cba.borrow();
    assert_eq!(borrowed, HgPath::new("a"));
}

#[test]
fn test_inclusive_ancestors() {
    let mut iter = WithBasename::inclusive_ancestors_of(HgPath::new("a/bb/c"));

    let next = iter.next().unwrap();
    assert_eq!(*next.full_path(), HgPath::new("a"));
    assert_eq!(next.base_name(), HgPath::new("a"));

    let next = iter.next().unwrap();
    assert_eq!(*next.full_path(), HgPath::new("a/bb"));
    assert_eq!(next.base_name(), HgPath::new("bb"));

    let next = iter.next().unwrap();
    assert_eq!(*next.full_path(), HgPath::new("a/bb/c"));
    assert_eq!(next.base_name(), HgPath::new("c"));

    assert!(iter.next().is_none());
}
