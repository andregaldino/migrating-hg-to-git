use byteorder::{BigEndian, ByteOrder};

/// A chunk of data to insert, delete or replace in a patch
///
/// A chunk is:
/// - an insertion when `!data.is_empty() && start == end`
/// - an deletion when `data.is_empty() && start < end`
/// - a replacement when `!data.is_empty() && start < end`
/// - not doing anything when `data.is_empty() && start == end`
#[derive(Debug, Clone)]
struct Chunk<'a> {
    /// The start position of the chunk of data to replace
    start: u32,
    /// The end position of the chunk of data to replace (open end interval)
    end: u32,
    /// The data replacing the chunk
    data: &'a [u8],
}

impl Chunk<'_> {
    /// Adjusted start of the chunk to replace.
    ///
    /// The offset, taking into account the growth/shrinkage of data
    /// induced by previously applied chunks.
    fn start_offset_by(&self, offset: i32) -> u32 {
        let start = self.start as i32 + offset;
        assert!(start >= 0, "negative chunk start should never happen");
        start as u32
    }

    /// Adjusted end of the chunk to replace.
    ///
    /// The offset, taking into account the growth/shrinkage of data
    /// induced by previously applied chunks.
    fn end_offset_by(&self, offset: i32) -> u32 {
        self.start_offset_by(offset) + self.data.len() as u32
    }

    /// Length of the replaced chunk.
    fn replaced_len(&self) -> u32 {
        self.end - self.start
    }

    /// Length difference between the replacing data and the replaced data.
    fn len_diff(&self) -> i32 {
        self.data.len() as i32 - self.replaced_len() as i32
    }
}

/// The delta between two revisions data.
#[derive(Debug, Clone)]
pub struct PatchList<'a> {
    /// A collection of chunks to apply.
    ///
    /// Those chunks are:
    /// - ordered from the left-most replacement to the right-most replacement
    /// - non-overlapping, meaning that two chucks can not change the same
    ///   chunk of the patched data
    chunks: Vec<Chunk<'a>>,
}

impl<'a> PatchList<'a> {
    /// Create a `PatchList` from bytes.
    pub fn new(data: &'a [u8]) -> Self {
        let mut chunks = vec![];
        let mut data = data;
        while !data.is_empty() {
            let start = BigEndian::read_u32(&data[0..]);
            let end = BigEndian::read_u32(&data[4..]);
            let len = BigEndian::read_u32(&data[8..]);
            assert!(start <= end);
            chunks.push(Chunk {
                start,
                end,
                data: &data[12..12 + (len as usize)],
            });
            data = &data[12 + (len as usize)..];
        }
        PatchList { chunks }
    }

    /// Return the final length of data after patching
    /// given its initial length .
    fn size(&self, initial_size: i32) -> i32 {
        self.chunks
            .iter()
            .fold(initial_size, |acc, chunk| acc + chunk.len_diff())
    }

    /// Apply the patch to some data.
    pub fn apply(&self, initial: &[u8]) -> Vec<u8> {
        let mut last: usize = 0;
        let mut vec =
            Vec::with_capacity(self.size(initial.len() as i32) as usize);
        for Chunk { start, end, data } in self.chunks.iter() {
            vec.extend(&initial[last..(*start as usize)]);
            vec.extend(data.iter());
            last = *end as usize;
        }
        vec.extend(&initial[last..]);
        vec
    }

    /// Combine two patch lists into a single patch list.
    ///
    /// Applying consecutive patches can lead to waste of time and memory
    /// as the changes introduced by one patch can be overridden by the next.
    /// Combining patches optimizes the whole patching sequence.
    fn combine(&mut self, other: &mut Self) -> Self {
        let mut chunks = vec![];

        // Keep track of each growth/shrinkage resulting from applying a chunk
        // in order to adjust the start/end of subsequent chunks.
        let mut offset = 0i32;

        // Keep track of the chunk of self.chunks to process.
        let mut pos = 0;

        // For each chunk of `other`, chunks of `self` are processed
        // until they start after the end of the current chunk.
        for Chunk { start, end, data } in other.chunks.iter() {
            // Add chunks of `self` that start before this chunk of `other`
            // without overlap.
            while pos < self.chunks.len()
                && self.chunks[pos].end_offset_by(offset) <= *start
            {
                let first = self.chunks[pos].clone();
                offset += first.len_diff();
                chunks.push(first);
                pos += 1;
            }

            // The current chunk of `self` starts before this chunk of `other`
            // with overlap.
            // The left-most part of data is added as an insertion chunk.
            // The right-most part data is kept in the chunk.
            if pos < self.chunks.len()
                && self.chunks[pos].start_offset_by(offset) < *start
            {
                let first = &mut self.chunks[pos];

                let (data_left, data_right) = first.data.split_at(
                    (*start - first.start_offset_by(offset)) as usize,
                );
                let left = Chunk {
                    start: first.start,
                    end: first.start,
                    data: data_left,
                };

                first.data = data_right;

                offset += left.len_diff();

                chunks.push(left);

                // There is no index incrementation because the right-most part
                // needs further examination.
            }

            // At this point remaining chunks of `self` starts after
            // the current chunk of `other`.

            // `start_offset` will be used to adjust the start of the current
            // chunk of `other`.
            // Offset tracking continues with `end_offset` to adjust the end
            // of the current chunk of `other`.
            let mut next_offset = offset;

            // Discard the chunks of `self` that are totally overridden
            // by the current chunk of `other`
            while pos < self.chunks.len()
                && self.chunks[pos].end_offset_by(next_offset) <= *end
            {
                let first = &self.chunks[pos];
                next_offset += first.len_diff();
                pos += 1;
            }

            // Truncate the left-most part of chunk of `self` that overlaps
            // the current chunk of `other`.
            if pos < self.chunks.len()
                && self.chunks[pos].start_offset_by(next_offset) < *end
            {
                let first = &mut self.chunks[pos];

                let how_much_to_discard =
                    *end - first.start_offset_by(next_offset);

                first.data = &first.data[(how_much_to_discard as usize)..];

                next_offset += how_much_to_discard as i32;
            }

            // Add the chunk of `other` with adjusted position.
            chunks.push(Chunk {
                start: (*start as i32 - offset) as u32,
                end: (*end as i32 - next_offset) as u32,
                data,
            });

            // Go back to normal offset tracking for the next `o` chunk
            offset = next_offset;
        }

        // Add remaining chunks of `self`.
        for elt in &self.chunks[pos..] {
            chunks.push(elt.clone());
        }
        PatchList { chunks }
    }
}

/// Combine a list of patch list into a single patch optimized patch list.
pub fn fold_patch_lists<'a>(lists: &[PatchList<'a>]) -> PatchList<'a> {
    if lists.len() <= 1 {
        if lists.is_empty() {
            PatchList { chunks: vec![] }
        } else {
            lists[0].clone()
        }
    } else {
        let (left, right) = lists.split_at(lists.len() / 2);
        let mut left_res = fold_patch_lists(left);
        let mut right_res = fold_patch_lists(right);
        left_res.combine(&mut right_res)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct PatchDataBuilder {
        data: Vec<u8>,
    }

    impl PatchDataBuilder {
        pub fn new() -> Self {
            Self { data: vec![] }
        }

        pub fn replace(
            &mut self,
            start: usize,
            end: usize,
            data: &[u8],
        ) -> &mut Self {
            assert!(start <= end);
            self.data.extend(&(start as i32).to_be_bytes());
            self.data.extend(&(end as i32).to_be_bytes());
            self.data.extend(&(data.len() as i32).to_be_bytes());
            self.data.extend(data.iter());
            self
        }

        pub fn get(&mut self) -> &[u8] {
            &self.data
        }
    }

    #[test]
    fn test_ends_before() {
        let data = vec![0u8, 0u8, 0u8];
        let mut patch1_data = PatchDataBuilder::new();
        patch1_data.replace(0, 1, &[1, 2]);
        let mut patch1 = PatchList::new(patch1_data.get());

        let mut patch2_data = PatchDataBuilder::new();
        patch2_data.replace(2, 4, &[3, 4]);
        let mut patch2 = PatchList::new(patch2_data.get());

        let patch = patch1.combine(&mut patch2);

        let result = patch.apply(&data);

        assert_eq!(result, vec![1u8, 2, 3, 4]);
    }

    #[test]
    fn test_starts_after() {
        let data = vec![0u8, 0u8, 0u8];
        let mut patch1_data = PatchDataBuilder::new();
        patch1_data.replace(2, 3, &[3]);
        let mut patch1 = PatchList::new(patch1_data.get());

        let mut patch2_data = PatchDataBuilder::new();
        patch2_data.replace(1, 2, &[1, 2]);
        let mut patch2 = PatchList::new(patch2_data.get());

        let patch = patch1.combine(&mut patch2);

        let result = patch.apply(&data);

        assert_eq!(result, vec![0u8, 1, 2, 3]);
    }

    #[test]
    fn test_overridden() {
        let data = vec![0u8, 0, 0];
        let mut patch1_data = PatchDataBuilder::new();
        patch1_data.replace(1, 2, &[3, 4]);
        let mut patch1 = PatchList::new(patch1_data.get());

        let mut patch2_data = PatchDataBuilder::new();
        patch2_data.replace(1, 4, &[1, 2, 3]);
        let mut patch2 = PatchList::new(patch2_data.get());

        let patch = patch1.combine(&mut patch2);

        let result = patch.apply(&data);

        assert_eq!(result, vec![0u8, 1, 2, 3]);
    }

    #[test]
    fn test_right_most_part_is_overridden() {
        let data = vec![0u8, 0, 0];
        let mut patch1_data = PatchDataBuilder::new();
        patch1_data.replace(0, 1, &[1, 3]);
        let mut patch1 = PatchList::new(patch1_data.get());

        let mut patch2_data = PatchDataBuilder::new();
        patch2_data.replace(1, 4, &[2, 3, 4]);
        let mut patch2 = PatchList::new(patch2_data.get());

        let patch = patch1.combine(&mut patch2);

        let result = patch.apply(&data);

        assert_eq!(result, vec![1u8, 2, 3, 4]);
    }

    #[test]
    fn test_left_most_part_is_overridden() {
        let data = vec![0u8, 0, 0];
        let mut patch1_data = PatchDataBuilder::new();
        patch1_data.replace(1, 3, &[1, 3, 4]);
        let mut patch1 = PatchList::new(patch1_data.get());

        let mut patch2_data = PatchDataBuilder::new();
        patch2_data.replace(0, 2, &[1, 2]);
        let mut patch2 = PatchList::new(patch2_data.get());

        let patch = patch1.combine(&mut patch2);

        let result = patch.apply(&data);

        assert_eq!(result, vec![1u8, 2, 3, 4]);
    }

    #[test]
    fn test_mid_is_overridden() {
        let data = vec![0u8, 0, 0];
        let mut patch1_data = PatchDataBuilder::new();
        patch1_data.replace(0, 3, &[1, 3, 3, 4]);
        let mut patch1 = PatchList::new(patch1_data.get());

        let mut patch2_data = PatchDataBuilder::new();
        patch2_data.replace(1, 3, &[2, 3]);
        let mut patch2 = PatchList::new(patch2_data.get());

        let patch = patch1.combine(&mut patch2);

        let result = patch.apply(&data);

        assert_eq!(result, vec![1u8, 2, 3, 4]);
    }
}
