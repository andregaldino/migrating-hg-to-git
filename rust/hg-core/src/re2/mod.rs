/// re2 module
///
/// The Python implementation of Mercurial uses the Re2 regex engine when
/// possible and if the bindings are installed, falling back to Python's `re`
/// in case of unsupported syntax (Re2 is a non-backtracking engine).
///
/// Using it from Rust is not ideal. We need C++ bindings, a C++ compiler,
/// Re2 needs to be installed... why not just use the `regex` crate?
///
/// Using Re2 from the Rust implementation guarantees backwards compatibility.
/// We know it will work out of the box without needing to figure out the
/// subtle differences in syntax. For example, `regex` currently does not
/// support empty alternations (regex like `a||b`) which happens more often
/// than we might think. Old benchmarks also showed worse performance from
/// regex than with Re2, but the methodology and results were lost, so take
/// this with a grain of salt.
///
/// The idea is to use Re2 for now as a temporary phase and then investigate
/// how much work would be needed to use `regex`.
mod re2;
pub use re2::Re2;
