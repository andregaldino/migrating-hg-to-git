use super::*;

/// Unit tests for:
///
/// ```ignore
/// fn compare_value(
///     current_merge: Revision,
///     merge_case_for_dest: impl Fn() -> MergeCase,
///     src_minor: &CopySource,
///     src_major: &CopySource,
/// ) -> (MergePick, /* overwrite: */ bool)
///  ```
#[test]
fn test_compare_value() {
    // The `compare_value!` macro calls the `compare_value` function with
    // arguments given in pseudo-syntax:
    //
    // * For `merge_case_for_dest` it takes a plain `MergeCase` value instead
    //   of a closure.
    // * `CopySource` values are represented as `(rev, path, overwritten)`
    //   tuples of type `(Revision, Option<PathToken>, OrdSet<Revision>)`.
    // * `PathToken` is an integer not read by `compare_value`. It only checks
    //   for `Some(_)` indicating a file copy v.s. `None` for a file deletion.
    // * `OrdSet<Revision>` is represented as a Python-like set literal.

    use MergeCase::*;
    use MergePick::*;

    assert_eq!(
        compare_value!(1, Normal, (1, None, { 1 }), (1, None, { 1 })),
        (Any, false)
    );
}

/// Unit tests for:
///
/// ```ignore
/// fn merge_copies_dict(
///     path_map: &TwoWayPathMap, // Not visible in test cases
///     current_merge: Revision,
///     minor: InternalPathCopies,
///     major: InternalPathCopies,
///     get_merge_case: impl Fn(&HgPath) -> MergeCase + Copy,
/// ) -> InternalPathCopies
/// ```
#[test]
fn test_merge_copies_dict() {
    // The `merge_copies_dict!` macro calls the `merge_copies_dict` function
    // with arguments given in pseudo-syntax:
    //
    // * `TwoWayPathMap` and path tokenization are implicitly taken care of.
    //   All paths are given as string literals.
    // * Key-value maps are represented with `{key1 => value1, key2 => value2}`
    //   pseudo-syntax.
    // * `InternalPathCopies` is a map of copy destination path keys to
    //   `CopySource` values.
    //   - `CopySource` is represented as a `(rev, source_path, overwritten)`
    //     tuple of type `(Revision, Option<Path>, OrdSet<Revision>)`.
    //   - Unlike in `test_compare_value`, source paths are string literals.
    //   - `OrdSet<Revision>` is again represented as a Python-like set
    //     literal.
    // * `get_merge_case` is represented as a map of copy destination path to
    //   `MergeCase`. The default for paths not in the map is
    //   `MergeCase::Normal`.
    //
    // `internal_path_copies!` creates an `InternalPathCopies` value with the
    // same pseudo-syntax as in `merge_copies_dict!`.

    use MergeCase::*;

    assert_eq!(
        merge_copies_dict!(
            1,
            {"foo" => (1, None, {})},
            {},
            {"foo" => Merged}
        ),
        internal_path_copies!("foo" => (1, None, {}))
    );
}

/// Unit tests for:
///
/// ```ignore
/// impl CombineChangesetCopies {
///     fn new(children_count: HashMap<Revision, usize>) -> Self
///
///     // Called repeatedly:
///     fn add_revision_inner<'a>(
///         &mut self,
///         rev: Revision,
///         p1: Revision,
///         p2: Revision,
///         copy_actions: impl Iterator<Item = Action<'a>>,
///         get_merge_case: impl Fn(&HgPath) -> MergeCase + Copy,
///     )
///
///     fn finish(mut self, target_rev: Revision) -> PathCopies
/// }
/// ```
#[test]
fn test_combine_changeset_copies() {
    // `combine_changeset_copies!` creates a `CombineChangesetCopies` with
    // `new`, then calls `add_revision_inner` repeatedly, then calls `finish`
    // for its return value.
    //
    // All paths given as string literals.
    //
    // * Key-value maps are represented with `{key1 => value1, key2 => value2}`
    //   pseudo-syntax.
    // * `children_count` is a map of revision numbers to count of children in
    //   the DAG. It includes all revisions that should be considered by the
    //   algorithm.
    // * Calls to `add_revision_inner` are represented as an array of anonymous
    //   structs with named fields, one pseudo-struct per call.
    //
    // `path_copies!` creates a `PathCopies` value, a map of copy destination
    // keys to copy source values. Note: the arrows for map literal syntax
    // point **backwards** compared to the logical direction of copy!

    use crate::NULL_REVISION as NULL;
    use Action::*;
    use MergeCase::*;

    assert_eq!(
        combine_changeset_copies!(
            { 1 => 1, 2 => 1 },
            [
                { rev: 1, p1: NULL, p2: NULL, actions: [], merge_cases: {}, },
                { rev: 2, p1: NULL, p2: NULL, actions: [], merge_cases: {}, },
                {
                    rev: 3, p1: 1, p2: 2,
                    actions: [CopiedFromP1("destination.txt", "source.txt")],
                    merge_cases: {"destination.txt" => Merged},
                },
            ],
            3,
        ),
        path_copies!("destination.txt" => "source.txt")
    );
}
