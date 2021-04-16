use crate::dirstate_tree::dirstate_map::DirstateMap;
use crate::matchers::Matcher;
use crate::DirstateStatus;
use crate::PatternFileWarning;
use crate::StatusError;
use crate::StatusOptions;
use std::path::PathBuf;

pub fn status<'a>(
    _dmap: &'a mut DirstateMap,
    _matcher: &'a (dyn Matcher + Sync),
    _root_dir: PathBuf,
    _ignore_files: Vec<PathBuf>,
    _options: StatusOptions,
) -> Result<(DirstateStatus<'a>, Vec<PatternFileWarning>), StatusError> {
    todo!()
}
