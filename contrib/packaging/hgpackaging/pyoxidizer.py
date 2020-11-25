# pyoxidizer.py - Packaging support for PyOxidizer
#
# Copyright 2020 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# no-check-code because Python 3 native.

import os
import pathlib
import shutil
import subprocess
import sys

from .downloads import download_entry
from .util import (
    extract_zip_to_directory,
    process_install_rules,
    find_vc_runtime_dll,
)


STAGING_RULES_WINDOWS = [
    ('contrib/bash_completion', 'contrib/'),
    ('contrib/hgk', 'contrib/hgk.tcl'),
    ('contrib/hgweb.fcgi', 'contrib/'),
    ('contrib/hgweb.wsgi', 'contrib/'),
    ('contrib/logo-droplets.svg', 'contrib/'),
    ('contrib/mercurial.el', 'contrib/'),
    ('contrib/mq.el', 'contrib/'),
    ('contrib/tcsh_completion', 'contrib/'),
    ('contrib/tcsh_completion_build.sh', 'contrib/'),
    ('contrib/vim/*', 'contrib/vim/'),
    ('contrib/win32/postinstall.txt', 'ReleaseNotes.txt'),
    ('contrib/win32/ReadMe.html', 'ReadMe.html'),
    ('contrib/xml.rnc', 'contrib/'),
    ('contrib/zsh_completion', 'contrib/'),
    ('doc/*.html', 'doc/'),
    ('doc/style.css', 'doc/'),
    ('COPYING', 'Copying.txt'),
]

STAGING_RULES_APP = [
    ('lib/mercurial/helptext/**/*.txt', 'helptext/'),
    ('lib/mercurial/defaultrc/*.rc', 'defaultrc/'),
    ('lib/mercurial/locale/**/*', 'locale/'),
    ('lib/mercurial/templates/**/*', 'templates/'),
]

STAGING_EXCLUDES_WINDOWS = [
    "doc/hg-ssh.8.html",
]


def run_pyoxidizer(
    source_dir: pathlib.Path,
    build_dir: pathlib.Path,
    out_dir: pathlib.Path,
    target_triple: str,
):
    """Build Mercurial with PyOxidizer and copy additional files into place.

    After successful completion, ``out_dir`` contains files constituting a
    Mercurial install.
    """
    # We need to make gettext binaries available for compiling i18n files.
    gettext_pkg, gettext_entry = download_entry('gettext', build_dir)
    gettext_dep_pkg = download_entry('gettext-dep', build_dir)[0]

    gettext_root = build_dir / ('gettext-win-%s' % gettext_entry['version'])

    if not gettext_root.exists():
        extract_zip_to_directory(gettext_pkg, gettext_root)
        extract_zip_to_directory(gettext_dep_pkg, gettext_root)

    env = dict(os.environ)
    env["PATH"] = "%s%s%s" % (
        env["PATH"],
        os.pathsep,
        str(gettext_root / "bin"),
    )

    args = [
        "pyoxidizer",
        "build",
        "--path",
        str(source_dir / "rust" / "hgcli"),
        "--release",
        "--target-triple",
        target_triple,
    ]

    subprocess.run(args, env=env, check=True)

    if "windows" in target_triple:
        target = "app_windows"
    else:
        target = "app_posix"

    build_dir = (
        source_dir / "build" / "pyoxidizer" / target_triple / "release" / target
    )

    if out_dir.exists():
        print("purging %s" % out_dir)
        shutil.rmtree(out_dir)

    # Now assemble all the files from PyOxidizer into the staging directory.
    shutil.copytree(build_dir, out_dir)

    # Move some of those files around. We can get rid of this once Mercurial
    # is taught to use the importlib APIs for reading resources.
    process_install_rules(STAGING_RULES_APP, build_dir, out_dir)

    # We also need to run setup.py build_doc to produce html files,
    # as they aren't built as part of ``pip install``.
    # This will fail if docutils isn't installed.
    subprocess.run(
        [sys.executable, str(source_dir / "setup.py"), "build_doc", "--html"],
        cwd=str(source_dir),
        check=True,
    )

    if "windows" in target_triple:
        process_install_rules(STAGING_RULES_WINDOWS, source_dir, out_dir)

        # Write out a default editor.rc file to configure notepad as the
        # default editor.
        os.makedirs(out_dir / "defaultrc", exist_ok=True)
        with (out_dir / "defaultrc" / "editor.rc").open(
            "w", encoding="utf-8"
        ) as fh:
            fh.write("[ui]\neditor = notepad\n")

        for f in STAGING_EXCLUDES_WINDOWS:
            p = out_dir / f
            if p.exists():
                print("removing %s" % p)
                p.unlink()

        # Add vcruntimeXXX.dll next to executable.
        vc_runtime_dll = find_vc_runtime_dll(x64="x86_64" in target_triple)
        shutil.copy(vc_runtime_dll, out_dir / vc_runtime_dll.name)
