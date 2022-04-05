use crate::{DirstateError, DirstateParents};

use super::dirstate_map::DirstateMap;
use std::ops::Deref;

use ouroboros::self_referencing;

/// Keep a `DirstateMap<'on_disk>` next to the `on_disk` buffer that it
/// borrows.
#[self_referencing]
pub struct OwningDirstateMap {
    on_disk: Box<dyn Deref<Target = [u8]> + Send>,
    #[borrows(on_disk)]
    #[covariant]
    map: DirstateMap<'this>,
}

impl OwningDirstateMap {
    pub fn new_empty<OnDisk>(on_disk: OnDisk) -> Self
    where
        OnDisk: Deref<Target = [u8]> + Send + 'static,
    {
        let on_disk = Box::new(on_disk);

        OwningDirstateMapBuilder {
            on_disk,
            map_builder: |bytes| DirstateMap::empty(&bytes),
        }
        .build()
    }

    pub fn new_v1<OnDisk>(
        on_disk: OnDisk,
    ) -> Result<(Self, DirstateParents), DirstateError>
    where
        OnDisk: Deref<Target = [u8]> + Send + 'static,
    {
        let on_disk = Box::new(on_disk);
        let mut parents = DirstateParents::NULL;

        Ok((
            OwningDirstateMapTryBuilder {
                on_disk,
                map_builder: |bytes| {
                    DirstateMap::new_v1(&bytes).map(|(dmap, p)| {
                        parents = p.unwrap_or(DirstateParents::NULL);
                        dmap
                    })
                },
            }
            .try_build()?,
            parents,
        ))
    }

    pub fn new_v2<OnDisk>(
        on_disk: OnDisk,
        data_size: usize,
        metadata: &[u8],
    ) -> Result<Self, DirstateError>
    where
        OnDisk: Deref<Target = [u8]> + Send + 'static,
    {
        let on_disk = Box::new(on_disk);

        OwningDirstateMapTryBuilder {
            on_disk,
            map_builder: |bytes| {
                DirstateMap::new_v2(&bytes, data_size, metadata)
            },
        }
        .try_build()
    }

    pub fn with_dmap_mut<R>(
        &mut self,
        f: impl FnOnce(&mut DirstateMap) -> R,
    ) -> R {
        self.with_map_mut(f)
    }

    pub fn get_map(&self) -> &DirstateMap {
        self.borrow_map()
    }

    pub fn on_disk(&self) -> &[u8] {
        self.borrow_on_disk()
    }
}
