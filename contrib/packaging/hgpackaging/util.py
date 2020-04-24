# util.py - Common packaging utility code.
#
# Copyright 2019 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# no-check-code because Python 3 native.

import distutils.version
import getpass
import glob
import os
import pathlib
import re
import shutil
import subprocess
import tarfile
import zipfile


def extract_tar_to_directory(source: pathlib.Path, dest: pathlib.Path):
    with tarfile.open(source, 'r') as tf:
        tf.extractall(dest)


def extract_zip_to_directory(source: pathlib.Path, dest: pathlib.Path):
    with zipfile.ZipFile(source, 'r') as zf:
        zf.extractall(dest)


def find_vc_runtime_dll(x64=False):
    """Finds Visual C++ Runtime DLL to include in distribution."""
    # We invoke vswhere to find the latest Visual Studio install.
    vswhere = (
        pathlib.Path(os.environ["ProgramFiles(x86)"])
        / "Microsoft Visual Studio"
        / "Installer"
        / "vswhere.exe"
    )

    if not vswhere.exists():
        raise Exception(
            "could not find vswhere.exe: %s does not exist" % vswhere
        )

    args = [
        str(vswhere),
        # -products * is necessary to return results from Build Tools
        # (as opposed to full IDE installs).
        "-products",
        "*",
        "-requires",
        "Microsoft.VisualCpp.Redist.14.Latest",
        "-latest",
        "-property",
        "installationPath",
    ]

    vs_install_path = pathlib.Path(
        os.fsdecode(subprocess.check_output(args).strip())
    )

    # This just gets us a path like
    # C:\Program Files (x86)\Microsoft Visual Studio\2019\Community
    # Actually vcruntime140.dll is under a path like:
    # VC\Redist\MSVC\<version>\<arch>\Microsoft.VC14<X>.CRT\vcruntime140.dll.

    arch = "x64" if x64 else "x86"

    search_glob = (
        r"%s\VC\Redist\MSVC\*\%s\Microsoft.VC14*.CRT\vcruntime140.dll"
        % (vs_install_path, arch)
    )

    candidates = glob.glob(search_glob, recursive=True)

    for candidate in reversed(candidates):
        return pathlib.Path(candidate)

    raise Exception("could not find vcruntime140.dll")


def find_legacy_vc_runtime_files(x64=False):
    """Finds Visual C++ Runtime DLLs to include in distribution."""
    winsxs = pathlib.Path(os.environ['SYSTEMROOT']) / 'WinSxS'

    prefix = 'amd64' if x64 else 'x86'

    candidates = sorted(
        p
        for p in os.listdir(winsxs)
        if p.lower().startswith('%s_microsoft.vc90.crt_' % prefix)
    )

    for p in candidates:
        print('found candidate VC runtime: %s' % p)

    # Take the newest version.
    version = candidates[-1]

    d = winsxs / version

    return [
        d / 'msvcm90.dll',
        d / 'msvcp90.dll',
        d / 'msvcr90.dll',
        winsxs / 'Manifests' / ('%s.manifest' % version),
    ]


def windows_10_sdk_info():
    """Resolves information about the Windows 10 SDK."""

    base = pathlib.Path(os.environ['ProgramFiles(x86)']) / 'Windows Kits' / '10'

    if not base.is_dir():
        raise Exception('unable to find Windows 10 SDK at %s' % base)

    # Find the latest version.
    bin_base = base / 'bin'

    versions = [v for v in os.listdir(bin_base) if v.startswith('10.')]
    version = sorted(versions, reverse=True)[0]

    bin_version = bin_base / version

    return {
        'root': base,
        'version': version,
        'bin_root': bin_version,
        'bin_x86': bin_version / 'x86',
        'bin_x64': bin_version / 'x64',
    }


def normalize_windows_version(version):
    """Normalize Mercurial version string so WiX/Inno accepts it.

    Version strings have to be numeric ``A.B.C[.D]`` to conform with MSI's
    requirements.

    We normalize RC version or the commit count to a 4th version component.
    We store this in the 4th component because ``A.B.C`` releases do occur
    and we want an e.g. ``5.3rc0`` version to be semantically less than a
    ``5.3.1rc2`` version. This requires always reserving the 3rd version
    component for the point release and the ``X.YrcN`` release is always
    point release 0.

    In the case of an RC and presence of ``+`` suffix data, we can't use both
    because the version format is limited to 4 components. We choose to use
    RC and throw away the commit count in the suffix. This means we could
    produce multiple installers with the same normalized version string.

    >>> normalize_windows_version("5.3")
    '5.3.0'

    >>> normalize_windows_version("5.3rc0")
    '5.3.0.0'

    >>> normalize_windows_version("5.3rc1")
    '5.3.0.1'

    >>> normalize_windows_version("5.3rc1+2-abcdef")
    '5.3.0.1'

    >>> normalize_windows_version("5.3+2-abcdef")
    '5.3.0.2'
    """
    if '+' in version:
        version, extra = version.split('+', 1)
    else:
        extra = None

    # 4.9rc0
    if version[:-1].endswith('rc'):
        rc = int(version[-1:])
        version = version[:-3]
    else:
        rc = None

    # Ensure we have at least X.Y version components.
    versions = [int(v) for v in version.split('.')]
    while len(versions) < 3:
        versions.append(0)

    if len(versions) < 4:
        if rc is not None:
            versions.append(rc)
        elif extra:
            # <commit count>-<hash>+<date>
            versions.append(int(extra.split('-')[0]))

    return '.'.join('%d' % x for x in versions[0:4])


def find_signtool():
    """Find signtool.exe from the Windows SDK."""
    sdk = windows_10_sdk_info()

    for key in ('bin_x64', 'bin_x86'):
        p = sdk[key] / 'signtool.exe'

        if p.exists():
            return p

    raise Exception('could not find signtool.exe in Windows 10 SDK')


def sign_with_signtool(
    file_path,
    description,
    subject_name=None,
    cert_path=None,
    cert_password=None,
    timestamp_url=None,
):
    """Digitally sign a file with signtool.exe.

    ``file_path`` is file to sign.
    ``description`` is text that goes in the signature.

    The signing certificate can be specified by ``cert_path`` or
    ``subject_name``. These correspond to the ``/f`` and ``/n`` arguments
    to signtool.exe, respectively.

    The certificate password can be specified via ``cert_password``. If
    not provided, you will be prompted for the password.

    ``timestamp_url`` is the URL of a RFC 3161 timestamp server (``/tr``
    argument to signtool.exe).
    """
    if cert_path and subject_name:
        raise ValueError('cannot specify both cert_path and subject_name')

    while cert_path and not cert_password:
        cert_password = getpass.getpass('password for %s: ' % cert_path)

    args = [
        str(find_signtool()),
        'sign',
        '/v',
        '/fd',
        'sha256',
        '/d',
        description,
    ]

    if cert_path:
        args.extend(['/f', str(cert_path), '/p', cert_password])
    elif subject_name:
        args.extend(['/n', subject_name])

    if timestamp_url:
        args.extend(['/tr', timestamp_url, '/td', 'sha256'])

    args.append(str(file_path))

    print('signing %s' % file_path)
    subprocess.run(args, check=True)


PRINT_PYTHON_INFO = '''
import platform; print("%s:%s" % (platform.architecture()[0], platform.python_version()))
'''.strip()


def python_exe_info(python_exe: pathlib.Path):
    """Obtain information about a Python executable."""

    res = subprocess.check_output([str(python_exe), '-c', PRINT_PYTHON_INFO])

    arch, version = res.decode('utf-8').split(':')

    version = distutils.version.LooseVersion(version)

    return {
        'arch': arch,
        'version': version,
        'py3': version >= distutils.version.LooseVersion('3'),
    }


def process_install_rules(
    rules: list, source_dir: pathlib.Path, dest_dir: pathlib.Path
):
    for source, dest in rules:
        if '*' in source:
            if not dest.endswith('/'):
                raise ValueError('destination must end in / when globbing')

            # We strip off the source path component before the first glob
            # character to construct the relative install path.
            prefix_end_index = source[: source.index('*')].rindex('/')
            relative_prefix = source_dir / source[0:prefix_end_index]

            for res in glob.glob(str(source_dir / source), recursive=True):
                source_path = pathlib.Path(res)

                if source_path.is_dir():
                    continue

                rel_path = source_path.relative_to(relative_prefix)

                dest_path = dest_dir / dest[:-1] / rel_path

                dest_path.parent.mkdir(parents=True, exist_ok=True)
                print('copying %s to %s' % (source_path, dest_path))
                shutil.copy(source_path, dest_path)

        # Simple file case.
        else:
            source_path = pathlib.Path(source)

            if dest.endswith('/'):
                dest_path = pathlib.Path(dest) / source_path.name
            else:
                dest_path = pathlib.Path(dest)

            full_source_path = source_dir / source_path
            full_dest_path = dest_dir / dest_path

            full_dest_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(full_source_path, full_dest_path)
            print('copying %s to %s' % (full_source_path, full_dest_path))


def read_version_py(source_dir):
    """Read the mercurial/__version__.py file to resolve the version string."""
    p = source_dir / 'mercurial' / '__version__.py'

    with p.open('r', encoding='utf-8') as fh:
        m = re.search('version = b"([^"]+)"', fh.read(), re.MULTILINE)

        if not m:
            raise Exception('could not parse %s' % p)

        return m.group(1)
