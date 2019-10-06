# __init__.py - Startup and module loading logic for Mercurial.
#
# Copyright 2015 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

from __future__ import absolute_import

import sys

# Allow 'from mercurial import demandimport' to keep working.
import hgdemandimport

demandimport = hgdemandimport

__all__ = []

# Python 3 uses a custom module loader that transforms source code between
# source file reading and compilation. This is done by registering a custom
# finder that changes the spec for Mercurial modules to use a custom loader.
if sys.version_info[0] >= 3:
    import importlib
    import importlib.abc
    import io
    import token
    import tokenize

    class hgpathentryfinder(importlib.abc.MetaPathFinder):
        """A sys.meta_path finder that uses a custom module loader."""

        def find_spec(self, fullname, path, target=None):
            # Only handle Mercurial-related modules.
            if not fullname.startswith('mercurial.'):
                return None
            # don't try to parse binary
            if fullname.startswith('mercurial.cext.'):
                return None
            # third-party packages are expected to be dual-version clean
            if fullname.startswith('mercurial.thirdparty'):
                return None
            # zstd is already dual-version clean, don't try and mangle it
            if fullname.startswith('mercurial.zstd'):
                return None
            # rustext is built for the right python version,
            # don't try and mangle it
            if fullname.startswith('mercurial.rustext'):
                return None

            # Try to find the module using other registered finders.
            spec = None
            for finder in sys.meta_path:
                if finder == self:
                    continue

                # Originally the API was a `find_module` method, but it was
                # renamed to `find_spec` in python 3.4, with a new `target`
                # argument.
                find_spec_method = getattr(finder, 'find_spec', None)
                if find_spec_method:
                    spec = find_spec_method(fullname, path, target=target)
                else:
                    spec = finder.find_module(fullname)
                    if spec is not None:
                        spec = importlib.util.spec_from_loader(fullname, spec)
                if spec:
                    break

            # This is a Mercurial-related module but we couldn't find it
            # using the previously-registered finders. This likely means
            # the module doesn't exist.
            if not spec:
                return None

            # TODO need to support loaders from alternate specs, like zip
            # loaders.
            loader = hgloader(spec.name, spec.origin)
            # Can't use util.safehasattr here because that would require
            # importing util, and we're in import code.
            if hasattr(spec.loader, 'loader'):  # hasattr-py3-only
                # This is a nested loader (maybe a lazy loader?)
                spec.loader.loader = loader
            else:
                spec.loader = loader
            return spec

    def replacetokens(tokens, fullname):
        """Transform a stream of tokens from raw to Python 3.

        It is called by the custom module loading machinery to rewrite
        source/tokens between source decoding and compilation.

        Returns a generator of possibly rewritten tokens.

        The input token list may be mutated as part of processing. However,
        its changes do not necessarily match the output token stream.

        REMEMBER TO CHANGE ``BYTECODEHEADER`` WHEN CHANGING THIS FUNCTION
        OR CACHED FILES WON'T GET INVALIDATED PROPERLY.
        """
        # The following utility functions access the tokens list and i index of
        # the for i, t enumerate(tokens) loop below
        def _isop(j, *o):
            """Assert that tokens[j] is an OP with one of the given values"""
            try:
                return tokens[j].type == token.OP and tokens[j].string in o
            except IndexError:
                return False

        for i, t in enumerate(tokens):
            # This looks like a function call.
            if t.type == token.NAME and _isop(i + 1, '('):
                fn = t.string

                # It changes iteritems/values to items/values as they are not
                # present in Python 3 world.
                if fn == 'iteritems' and not (
                    tokens[i - 1].type == token.NAME
                    and tokens[i - 1].string == 'def'
                ):
                    yield t._replace(string=fn[4:])
                    continue

            # Emit unmodified token.
            yield t

    # Header to add to bytecode files. This MUST be changed when
    # ``replacetoken`` or any mechanism that changes semantics of module
    # loading is changed. Otherwise cached bytecode may get loaded without
    # the new transformation mechanisms applied.
    BYTECODEHEADER = b'HG\x00\x16'

    class hgloader(importlib.machinery.SourceFileLoader):
        """Custom module loader that transforms source code.

        When the source code is converted to a code object, we transform
        certain patterns to be Python 3 compatible. This allows us to write code
        that is natively Python 2 and compatible with Python 3 without
        making the code excessively ugly.

        We do this by transforming the token stream between parse and compile.

        Implementing transformations invalidates caching assumptions made
        by the built-in importer. The built-in importer stores a header on
        saved bytecode files indicating the Python/bytecode version. If the
        version changes, the cached bytecode is ignored. The Mercurial
        transformations could change at any time. This means we need to check
        that cached bytecode was generated with the current transformation
        code or there could be a mismatch between cached bytecode and what
        would be generated from this class.

        We supplement the bytecode caching layer by wrapping ``get_data``
        and ``set_data``. These functions are called when the
        ``SourceFileLoader`` retrieves and saves bytecode cache files,
        respectively. We simply add an additional header on the file. As
        long as the version in this file is changed when semantics change,
        cached bytecode should be invalidated when transformations change.

        The added header has the form ``HG<VERSION>``. That is a literal
        ``HG`` with 2 binary bytes indicating the transformation version.
        """

        def get_data(self, path):
            data = super(hgloader, self).get_data(path)

            if not path.endswith(tuple(importlib.machinery.BYTECODE_SUFFIXES)):
                return data

            # There should be a header indicating the Mercurial transformation
            # version. If it doesn't exist or doesn't match the current version,
            # we raise an OSError because that is what
            # ``SourceFileLoader.get_code()`` expects when loading bytecode
            # paths to indicate the cached file is "bad."
            if data[0:2] != b'HG':
                raise OSError('no hg header')
            if data[0:4] != BYTECODEHEADER:
                raise OSError('hg header version mismatch')

            return data[4:]

        def set_data(self, path, data, *args, **kwargs):
            if path.endswith(tuple(importlib.machinery.BYTECODE_SUFFIXES)):
                data = BYTECODEHEADER + data

            return super(hgloader, self).set_data(path, data, *args, **kwargs)

        def source_to_code(self, data, path):
            """Perform token transformation before compilation."""
            buf = io.BytesIO(data)
            tokens = tokenize.tokenize(buf.readline)
            data = tokenize.untokenize(replacetokens(list(tokens), self.name))
            # Python's built-in importer strips frames from exceptions raised
            # for this code. Unfortunately, that mechanism isn't extensible
            # and our frame will be blamed for the import failure. There
            # are extremely hacky ways to do frame stripping. We haven't
            # implemented them because they are very ugly.
            return super(hgloader, self).source_to_code(data, path)

    # We automagically register our custom importer as a side-effect of
    # loading. This is necessary to ensure that any entry points are able
    # to import mercurial.* modules without having to perform this
    # registration themselves.
    if not any(isinstance(x, hgpathentryfinder) for x in sys.meta_path):
        # meta_path is used before any implicit finders and before sys.path.
        sys.meta_path.insert(0, hgpathentryfinder())
