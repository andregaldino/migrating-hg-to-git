"""test line matching with some failing examples and some which warn

run-test.t only checks positive matches and can not see warnings
(both by design)
"""


import doctest, os, re
run_tests = __import__('run-tests')

def lm(expected, output):
    r"""check if output matches expected

    does it generally work?
        >>> lm('H*e (glob)\n', 'Here\n')
        True

    fail on bad test data
        >>> try: lm('a\n','a')
        ... except AssertionError, ex: print ex
        missing newline
        >>> try: lm('single backslash\n', 'single \backslash\n')
        ... except AssertionError, ex: print ex
        single backslash or unknown char
    """
    assert expected.endswith('\n') and output.endswith('\n'), 'missing newline'
    assert not re.search(r'[^ \w\\/\r\n()*?]', expected + output), \
           'single backslash or unknown char'
    match = run_tests.linematch(expected, output)
    return bool(match)

def wintests():
    r"""test matching like running on windows

    enable windows matching on any os
        >>> _osaltsep = os.altsep
        >>> os.altsep = True

    valid match on windows
        >>> lm('g/a*/d (glob)\n', 'g\\abc/d\n')
        True

    direct matching, glob unnecessary
        >>> lm('g/b (glob)\n', 'g/b\n')
        <BLANKLINE>
        Info, unnecessary glob: g/b (glob)
        True

    missing glob
        >>> lm('/g/c/d/fg\n', '\\g\\c\\d/fg\n')
        False

    restore os.altsep
        >>> os.altsep = _osaltsep
    """
    os.altsep # for pyflakes, because it does not see os in the doctest

def otherostests():
    r"""test matching like running on non-windows os

    disable windows matching on any os
        >>> _osaltsep = os.altsep
        >>> os.altsep = False

    backslash does not match slash
        >>> lm('h/a* (glob)\n', 'h\\ab\n')
        False

    direct matching glob can not be recognized
        >>> lm('h/b (glob)\n', 'h/b\n')
        True

    missing glob can not not be recognized
        >>> lm('/h/c/df/g/\n', '\\h/c\\df/g\\\n')
        False

    restore os.altsep
        >>> os.altsep = _osaltsep
    """
    pass

if __name__ == '__main__':
    doctest.testmod()
