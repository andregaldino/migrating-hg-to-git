pub mod files;

pub fn replace_slice<T>(buf: &mut [T], from: &[T], to: &[T])
where
    T: Clone + PartialEq,
{
    if buf.len() < from.len() || from.len() != to.len() {
        return;
    }
    for i in 0..=buf.len() - from.len() {
        if buf[i..].starts_with(from) {
            buf[i..(i + from.len())].clone_from_slice(to);
        }
    }
}

pub trait SliceExt {
    fn trim(&self) -> &Self;
    fn trim_end(&self) -> &Self;
}

fn is_not_whitespace(c: &u8) -> bool {
    !(*c as char).is_whitespace()
}

impl SliceExt for [u8] {
    fn trim(&self) -> &[u8] {
        if let Some(first) = self.iter().position(is_not_whitespace) {
            if let Some(last) = self.iter().rposition(is_not_whitespace) {
                &self[first..last + 1]
            } else {
                unreachable!();
            }
        } else {
            &[]
        }
    }
    fn trim_end(&self) -> &[u8] {
        if let Some(last) = self.iter().rposition(is_not_whitespace) {
            &self[..last + 1]
        } else {
            &[]
        }
    }
}
