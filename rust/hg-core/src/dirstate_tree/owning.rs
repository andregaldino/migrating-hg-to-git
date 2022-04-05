use super::dirstate_map::DirstateMap;
use stable_deref_trait::StableDeref;
use std::ops::Deref;

/*
// /!\ This is unsound and can cause use after free. It will be fixed in the
// next patch

// If we change `value` from its current use of `HgPathBuf` to `&HgPath`,
// nothing here tells that `value` will outlive `OwningDirstateMap`
pub fn copy_map_insert<'a,'owned>(
    &'owned mut self,
    key: &HgPath,
    value: &'a HgPath,
) -> Result<Option<HgPathBuf>, DirstateV2ParseError> {
    // `'local` is smaller than `'a` here
    let map: &'local mut DirstateMap<'local> = self.get_map_mut();
    let node: &'local mut Node<'local> = DirstateMap::get_or_insert_node(
        map.on_disk,
        &mut map.unreachable_bytes,
        &mut map.root,
        &key,
        WithBasename::to_cow_owned,
        |_ancestor| {},
    )?;
    if node.copy_source.is_none() {
        map.nodes_with_copy_source_count += 1
    }
    Ok(node.copy_source.replace(value.into()).map(Cow::into_owned))
    // and right here ----------^^^^^^^^^^^^
    // we are storing `&'a HgPath` in `Node<'local>` which is possible
    // because to the compiler, `'a` is longer than ``local`.
    // It is wrong because nothing proves that `&'a HgPath` will outlive `self`.
}

// All of this is caused by the wrong cast of the DirstateMap pointer that
// fakes the lifetime of `DirstateMap` and ensures the compiler that it lives
// as long as `on_disk`, which is only true for its immutable data.
// This will be fixed in the next commit.
*/

/// Keep a `DirstateMap<'on_disk>` next to the `on_disk` buffer that it
/// borrows.
///
/// This is similar to [`OwningRef`] which is more limited because it
/// represents exactly one `&T` reference next to the value it borrows, as
/// opposed to a struct that may contain an arbitrary number of references in
/// arbitrarily-nested data structures.
///
/// [`OwningRef`]: https://docs.rs/owning_ref/0.4.1/owning_ref/struct.OwningRef.html
pub struct OwningDirstateMap {
    /// Owned handle to a bytes buffer with a stable address.
    ///
    /// See <https://docs.rs/owning_ref/0.4.1/owning_ref/trait.StableAddress.html>.
    on_disk: Box<dyn Deref<Target = [u8]> + Send>,

    /// Pointer for `Box<DirstateMap<'on_disk>>`, typed-erased because the
    /// language cannot represent a lifetime referencing a sibling field.
    /// This is not quite a self-referencial struct (moving this struct is not
    /// a problem as it doesn’t change the address of the bytes buffer owned
    /// by `on_disk`) but touches similar borrow-checker limitations.
    ptr: *mut (),
}

impl OwningDirstateMap {
    pub fn new_empty<OnDisk>(on_disk: OnDisk) -> Self
    where
        OnDisk: Deref<Target = [u8]> + StableDeref + Send + 'static,
    {
        let on_disk = Box::new(on_disk);
        let bytes: &'_ [u8] = &on_disk;
        let map = DirstateMap::empty(bytes);

        // Like in `bytes` above, this `'_` lifetime parameter borrows from
        // the bytes buffer owned by `on_disk`.
        let ptr: *mut DirstateMap<'_> = Box::into_raw(Box::new(map));

        // Erase the pointed type entirely in order to erase the lifetime.
        let ptr: *mut () = ptr.cast();

        Self { on_disk, ptr }
    }

    pub fn get_pair_mut<'a>(
        &'a mut self,
    ) -> (&'a [u8], &'a mut DirstateMap<'a>) {
        // SAFETY: We cast the type-erased pointer back to the same type it had
        // in `new`, except with a different lifetime parameter. This time we
        // connect the lifetime to that of `self`. This cast is valid because
        // `self` owns the same `on_disk` whose buffer `DirstateMap`
        // references. That buffer has a stable memory address because our
        // `Self::new_empty` counstructor requires `StableDeref`.
        let ptr: *mut DirstateMap<'a> = self.ptr.cast();
        // SAFETY: we dereference that pointer, connecting the lifetime of the
        // new `&mut` to that of `self`. This is valid because the
        // raw pointer is to a boxed value, and `self` owns that box.
        (&self.on_disk, unsafe { &mut *ptr })
    }

    pub fn get_map_mut<'a>(&'a mut self) -> &'a mut DirstateMap<'a> {
        self.get_pair_mut().1
    }

    pub fn get_map<'a>(&'a self) -> &'a DirstateMap<'a> {
        // SAFETY: same reasoning as in `get_pair_mut` above.
        let ptr: *mut DirstateMap<'a> = self.ptr.cast();
        unsafe { &*ptr }
    }

    pub fn on_disk<'a>(&'a self) -> &'a [u8] {
        &self.on_disk
    }
}

impl Drop for OwningDirstateMap {
    fn drop(&mut self) {
        // Silence a "field is never read" warning, and demonstrate that this
        // value is still alive.
        let _: &Box<dyn Deref<Target = [u8]> + Send> = &self.on_disk;
        // SAFETY: this cast is the same as in `get_mut`, and is valid for the
        // same reason. `self.on_disk` still exists at this point, drop glue
        // will drop it implicitly after this `drop` method returns.
        let ptr: *mut DirstateMap<'_> = self.ptr.cast();
        // SAFETY: `Box::from_raw` takes ownership of the box away from `self`.
        // This is fine because drop glue does nothing for `*mut ()` and we’re
        // in `drop`, so `get` and `get_mut` cannot be called again.
        unsafe { drop(Box::from_raw(ptr)) }
    }
}

fn _static_assert_is_send<T: Send>() {}

fn _static_assert_fields_are_send() {
    _static_assert_is_send::<Box<DirstateMap<'_>>>();
}

// SAFETY: we don’t get this impl implicitly because `*mut (): !Send` because
// thread-safety of raw pointers is unknown in the general case. However this
// particular raw pointer represents a `Box<DirstateMap<'on_disk>>` that we
// own. Since that `Box` is `Send` as shown in above, it is sound to mark
// this struct as `Send` too.
unsafe impl Send for OwningDirstateMap {}
