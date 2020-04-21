# cli.py - Command line interface for automation
#
# Copyright 2019 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# no-check-code because Python 3 native.

import argparse
import os
import pathlib

from . import (
    inno,
    wix,
)

HERE = pathlib.Path(os.path.abspath(os.path.dirname(__file__)))
SOURCE_DIR = HERE.parent.parent.parent


def build_inno(pyoxidizer_target=None, python=None, iscc=None, version=None):
    if not pyoxidizer_target and not python:
        raise Exception("--python required unless building with PyOxidizer")

    if python and not os.path.isabs(python):
        raise Exception("--python arg must be an absolute path")

    if iscc:
        iscc = pathlib.Path(iscc)
    else:
        iscc = (
            pathlib.Path(os.environ["ProgramFiles(x86)"])
            / "Inno Setup 5"
            / "ISCC.exe"
        )

    build_dir = SOURCE_DIR / "build"

    if pyoxidizer_target:
        inno.build_with_pyoxidizer(
            SOURCE_DIR, build_dir, pyoxidizer_target, iscc, version=version
        )
    else:
        inno.build_with_py2exe(
            SOURCE_DIR, build_dir, pathlib.Path(python), iscc, version=version,
        )


def build_wix(
    name=None,
    pyoxidizer_target=None,
    python=None,
    version=None,
    sign_sn=None,
    sign_cert=None,
    sign_password=None,
    sign_timestamp_url=None,
    extra_packages_script=None,
    extra_wxs=None,
    extra_features=None,
):
    if not pyoxidizer_target and not python:
        raise Exception("--python required unless building with PyOxidizer")

    if python and not os.path.isabs(python):
        raise Exception("--python arg must be an absolute path")

    kwargs = {
        "source_dir": SOURCE_DIR,
        "version": version,
    }

    if pyoxidizer_target:
        fn = wix.build_installer_pyoxidizer
        kwargs["target_triple"] = pyoxidizer_target
    else:
        fn = wix.build_installer_py2exe
        kwargs["python_exe"] = pathlib.Path(python)

    if extra_packages_script:
        if pyoxidizer_target:
            raise Exception(
                "pyoxidizer does not support --extra-packages-script"
            )
        kwargs["extra_packages_script"] = extra_packages_script
    if extra_wxs:
        kwargs["extra_wxs"] = dict(
            thing.split("=") for thing in extra_wxs.split(",")
        )
    if extra_features:
        kwargs["extra_features"] = extra_features.split(",")

    if sign_sn or sign_cert:
        kwargs["signing_info"] = {
            "name": name,
            "subject_name": sign_sn,
            "cert_path": sign_cert,
            "cert_password": sign_password,
            "timestamp_url": sign_timestamp_url,
        }

    fn(**kwargs)


def get_parser():
    parser = argparse.ArgumentParser()

    subparsers = parser.add_subparsers()

    sp = subparsers.add_parser("inno", help="Build Inno Setup installer")
    sp.add_argument(
        "--pyoxidizer-target",
        choices={"i686-pc-windows-msvc", "x86_64-pc-windows-msvc"},
        help="Build with PyOxidizer targeting this host triple",
    )
    sp.add_argument("--python", help="path to python.exe to use")
    sp.add_argument("--iscc", help="path to iscc.exe to use")
    sp.add_argument(
        "--version",
        help="Mercurial version string to use "
        "(detected from __version__.py if not defined",
    )
    sp.set_defaults(func=build_inno)

    sp = subparsers.add_parser(
        "wix", help="Build Windows installer with WiX Toolset"
    )
    sp.add_argument("--name", help="Application name", default="Mercurial")
    sp.add_argument(
        "--pyoxidizer-target",
        choices={"i686-pc-windows-msvc", "x86_64-pc-windows-msvc"},
        help="Build with PyOxidizer targeting this host triple",
    )
    sp.add_argument("--python", help="Path to Python executable to use")
    sp.add_argument(
        "--sign-sn",
        help="Subject name (or fragment thereof) of certificate "
        "to use for signing",
    )
    sp.add_argument(
        "--sign-cert", help="Path to certificate to use for signing"
    )
    sp.add_argument("--sign-password", help="Password for signing certificate")
    sp.add_argument(
        "--sign-timestamp-url",
        help="URL of timestamp server to use for signing",
    )
    sp.add_argument("--version", help="Version string to use")
    sp.add_argument(
        "--extra-packages-script",
        help=(
            "Script to execute to include extra packages in " "py2exe binary."
        ),
    )
    sp.add_argument(
        "--extra-wxs", help="CSV of path_to_wxs_file=working_dir_for_wxs_file"
    )
    sp.add_argument(
        "--extra-features",
        help=(
            "CSV of extra feature names to include "
            "in the installer from the extra wxs files"
        ),
    )
    sp.set_defaults(func=build_wix)

    return parser


def main():
    parser = get_parser()
    args = parser.parse_args()

    if not hasattr(args, "func"):
        parser.print_help()
        return

    kwargs = dict(vars(args))
    del kwargs["func"]

    args.func(**kwargs)
