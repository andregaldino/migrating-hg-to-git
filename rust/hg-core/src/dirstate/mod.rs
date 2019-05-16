pub mod parsers;

#[derive(Debug, PartialEq, Copy, Clone)]
pub struct DirstateParents<'a> {
    pub p1: &'a [u8],
    pub p2: &'a [u8],
}

/// The C implementation uses all signed types. This will be an issue
/// either when 4GB+ source files are commonplace or in 2038, whichever
/// comes first.
#[derive(Debug, PartialEq)]
pub struct DirstateEntry {
    pub state: i8,
    pub mode: i32,
    pub mtime: i32,
    pub size: i32,
}

pub type DirstateVec = Vec<(Vec<u8>, DirstateEntry)>;

#[derive(Debug, PartialEq)]
pub struct CopyVecEntry<'a> {
    pub path: &'a [u8],
    pub copy_path: &'a [u8],
}

pub type CopyVec<'a> = Vec<CopyVecEntry<'a>>;
