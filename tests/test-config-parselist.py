"""
List-valued configuration keys have an ad-hoc microsyntax. From `hg help config`:

> List values are separated by whitespace or comma, except when values are
> placed in double quotation marks:
>
>     allow_read = "John Doe, PhD", brian, betty
>
> Quotation marks can be escaped by prefixing them with a backslash. Only
> quotation marks at the beginning of a word is counted as a quotation
> (e.g., ``foo"bar baz`` is the list of ``foo"bar`` and ``baz``).

That help documentation is fairly light on details, the actual parser has many
other edge cases. This test tries to cover them.
"""

from mercurial.utils import stringutil


def assert_parselist(input, expected):
    result = stringutil.parselist(input)
    if result != expected:
        raise AssertionError(
            "parse_input(%r)\n     got %r\nexpected %r"
            % (input, result, expected)
        )


# Keep these Python tests in sync with the Rust ones in `rust/hg-core/src/config/values.rs`

assert_parselist(b'', [])
assert_parselist(b',', [])
assert_parselist(b'A', [b'A'])
assert_parselist(b'B,B', [b'B', b'B'])
assert_parselist(b', C, ,C,', [b'C', b'C'])
assert_parselist(b'"', [b'"'])
assert_parselist(b'""', [b'', b''])
assert_parselist(b'D,"', [b'D', b'"'])
assert_parselist(b'E,""', [b'E', b'', b''])
assert_parselist(b'"F,F"', [b'F,F'])
assert_parselist(b'"G,G', [b'"G', b'G'])
assert_parselist(b'"H \\",\\"H', [b'"H', b',', b'H'])
assert_parselist(b'I,I"', [b'I', b'I"'])
assert_parselist(b'J,"J', [b'J', b'"J'])
assert_parselist(b'K K', [b'K', b'K'])
assert_parselist(b'"K" K', [b'K', b'K'])
assert_parselist(b'L\tL', [b'L', b'L'])
assert_parselist(b'"L"\tL', [b'L', b'', b'L'])
assert_parselist(b'M\x0bM', [b'M', b'M'])
assert_parselist(b'"M"\x0bM', [b'M', b'', b'M'])
assert_parselist(b'"N"  , ,"', [b'N"'])
assert_parselist(b'" ,O,  ', [b'"', b'O'])
