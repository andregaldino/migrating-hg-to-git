//! Supporting macros for `tests.rs` in the same directory.
//! See comments there for usage.

/// Python-like set literal
macro_rules! set {
    (
        $Type: ty {
            $( $value: expr ),* $(,)?
        }
    ) => {{
        #[allow(unused_mut)]
        let mut set = <$Type>::new();
        $( set.insert($value); )*
        set
    }}
}

/// `{key => value}` map literal
macro_rules! map {
    (
        $Type: ty {
            $( $key: expr => $value: expr ),* $(,)?
        }
    ) => {{
        #[allow(unused_mut)]
        let mut set = <$Type>::new();
        $( set.insert($key, $value); )*
        set
    }}
}

macro_rules! copy_source {
    ($rev: expr, $path: expr, $overwritten: tt) => {
        CopySource {
            rev: $rev,
            path: $path,
            overwritten: set!(OrdSet<Revision> $overwritten),
        }
    };
}

macro_rules! compare_value {
    (
        $merge_revision: expr,
        $merge_case_for_dest: ident,
        ($min_rev: expr, $min_path: expr, $min_overwrite: tt),
        ($maj_rev: expr, $maj_path: expr, $maj_overwrite: tt) $(,)?
    ) => {
        compare_value(
            $merge_revision,
            || $merge_case_for_dest,
            &copy_source!($min_rev, $min_path, $min_overwrite),
            &copy_source!($maj_rev, $maj_path, $maj_overwrite),
        )
    };
}

macro_rules! tokenized_path_copies {
    (
        $path_map: ident, {$(
            $dest: expr => (
                $src_rev: expr,
                $src_path: expr,
                $src_overwrite: tt
            )
        ),*}
        $(,)*
    ) => {
        map!(InternalPathCopies {$(
            $path_map.tokenize(HgPath::new($dest)) =>
            copy_source!(
                $src_rev,
                Option::map($src_path, |p: &str| {
                    $path_map.tokenize(HgPath::new(p))
                }),
                $src_overwrite
            )
        )*})
    }
}

macro_rules! merge_case_callback {
    (
        $( $merge_path: expr => $merge_case: ident ),*
        $(,)?
    ) => {
        #[allow(unused)]
        |merge_path| -> MergeCase {
            $(
                if (merge_path == HgPath::new($merge_path)) {
                    return $merge_case
                }
            )*
            MergeCase::Normal
        }
    };
}

macro_rules! merge_copies_dict {
    (
        $current_merge: expr,
        $minor_copies: tt,
        $major_copies: tt,
        $get_merge_case: tt $(,)?
    ) => {
        {
            #[allow(unused_mut)]
            let mut map = TwoWayPathMap::default();
            let minor = tokenized_path_copies!(map, $minor_copies);
            let major = tokenized_path_copies!(map, $major_copies);
            merge_copies_dict(
                &map, $current_merge, minor, major,
                merge_case_callback! $get_merge_case,
            )
            .into_iter()
            .map(|(token, source)| {
                (
                    map.untokenize(token).to_string(),
                    (
                        source.rev,
                        source.path.map(|t| map.untokenize(t).to_string()),
                        source.overwritten.into_iter().collect(),
                    ),
                )
            })
            .collect::<OrdMap<
                String,
                (Revision, Option<String>, OrdSet<Revision>)
            >>()
        }
    };
}

macro_rules! internal_path_copies {
    (
        $(
            $dest: expr => (
                $src_rev: expr,
                $src_path: expr,
                $src_overwrite: tt $(,)?
            )
        ),*
        $(,)*
    ) => {
        map!(OrdMap<_, _> {$(
            String::from($dest) => (
                $src_rev,
                $src_path,
                set!(OrdSet<Revision> $src_overwrite)
            )
        ),*})
    };
}

macro_rules! combine_changeset_copies {
    (
        $children_count: tt,
        [
            $(
                {
                    rev: $rev: expr,
                    p1: $p1: expr,
                    p2: $p2: expr,
                    actions: [
                        $(
                            $Action: ident($( $action_path: expr ),+)
                        ),*
                        $(,)?
                    ],
                    merge_cases: $merge: tt
                    $(,)?
                }
            ),*
            $(,)?
        ],
        $target_rev: expr $(,)*
    ) => {{
        let count = map!(HashMap<Revision, usize> $children_count);
        let mut combine_changeset_copies = CombineChangesetCopies::new(count);
        $(
            let actions = vec![$(
                $Action($( HgPath::new($action_path) ),*)
            ),*];
            combine_changeset_copies.add_revision_inner(
                $rev, $p1, $p2, actions.into_iter(),
                merge_case_callback! $merge
            );
        )*
        combine_changeset_copies.finish($target_rev)
    }};
}

macro_rules! path_copies {
    (
        $( $expected_destination: expr => $expected_source: expr ),* $(,)?
    ) => {
        map!(PathCopies {$(
            HgPath::new($expected_destination).to_owned()
                => HgPath::new($expected_source).to_owned(),
        ),*})
    };
}
