# wix.py - WiX installer functionality
#
# Copyright 2019 Gregory Szorc <gregory.szorc@gmail.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

# no-check-code because Python 3 native.

import collections
import os
import pathlib
import re
import shutil
import subprocess
import typing
import uuid
import xml.dom.minidom

from .downloads import download_entry
from .py2exe import (
    build_py2exe,
    stage_install,
)
from .util import (
    extract_zip_to_directory,
    normalize_windows_version,
    process_install_rules,
    sign_with_signtool,
)


EXTRA_PACKAGES = {
    'dulwich',
    'distutils',
    'keyring',
    'pygments',
    'win32ctypes',
}


EXTRA_INSTALL_RULES = [
    ('contrib/packaging/wix/COPYING.rtf', 'COPYING.rtf'),
    ('contrib/win32/mercurial.ini', 'defaultrc/mercurial.rc'),
]

STAGING_REMOVE_FILES = [
    # We use the RTF variant.
    'copying.txt',
]

SHORTCUTS = {
    # hg.1.html'
    'hg.file.5d3e441c_28d9_5542_afd0_cdd4234f12d5': {
        'Name': 'Mercurial Command Reference',
    },
    # hgignore.5.html
    'hg.file.5757d8e0_f207_5e10_a2ec_3ba0a062f431': {
        'Name': 'Mercurial Ignore Files',
    },
    # hgrc.5.html
    'hg.file.92e605fd_1d1a_5dc6_9fc0_5d2998eb8f5e': {
        'Name': 'Mercurial Configuration Files',
    },
}


def find_version(source_dir: pathlib.Path):
    version_py = source_dir / 'mercurial' / '__version__.py'

    with version_py.open('r', encoding='utf-8') as fh:
        source = fh.read().strip()

    m = re.search('version = b"(.*)"', source)
    return m.group(1)


def ensure_vc90_merge_modules(build_dir):
    x86 = (
        download_entry(
            'vc9-crt-x86-msm',
            build_dir,
            local_name='microsoft.vcxx.crt.x86_msm.msm',
        )[0],
        download_entry(
            'vc9-crt-x86-msm-policy',
            build_dir,
            local_name='policy.x.xx.microsoft.vcxx.crt.x86_msm.msm',
        )[0],
    )

    x64 = (
        download_entry(
            'vc9-crt-x64-msm',
            build_dir,
            local_name='microsoft.vcxx.crt.x64_msm.msm',
        )[0],
        download_entry(
            'vc9-crt-x64-msm-policy',
            build_dir,
            local_name='policy.x.xx.microsoft.vcxx.crt.x64_msm.msm',
        )[0],
    )
    return {
        'x86': x86,
        'x64': x64,
    }


def run_candle(wix, cwd, wxs, source_dir, defines=None):
    args = [
        str(wix / 'candle.exe'),
        '-nologo',
        str(wxs),
        '-dSourceDir=%s' % source_dir,
    ]

    if defines:
        args.extend('-d%s=%s' % define for define in sorted(defines.items()))

    subprocess.run(args, cwd=str(cwd), check=True)


def make_post_build_signing_fn(
    name,
    subject_name=None,
    cert_path=None,
    cert_password=None,
    timestamp_url=None,
):
    """Create a callable that will use signtool to sign hg.exe."""

    def post_build_sign(source_dir, build_dir, dist_dir, version):
        description = '%s %s' % (name, version)

        sign_with_signtool(
            dist_dir / 'hg.exe',
            description,
            subject_name=subject_name,
            cert_path=cert_path,
            cert_password=cert_password,
            timestamp_url=timestamp_url,
        )

    return post_build_sign


def make_files_xml(staging_dir: pathlib.Path, is_x64) -> str:
    """Create XML string listing every file to be installed."""

    # We derive GUIDs from a deterministic file path identifier.
    # We shoehorn the name into something that looks like a URL because
    # the UUID namespaces are supposed to work that way (even though
    # the input data probably is never validated).

    doc = xml.dom.minidom.parseString(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">'
        '</Wix>'
    )

    # Assemble the install layout by directory. This makes it easier to
    # emit XML, since each directory has separate entities.
    manifest = collections.defaultdict(dict)

    for root, dirs, files in os.walk(staging_dir):
        dirs.sort()

        root = pathlib.Path(root)
        rel_dir = root.relative_to(staging_dir)

        for i in range(len(rel_dir.parts)):
            parent = '/'.join(rel_dir.parts[0 : i + 1])
            manifest.setdefault(parent, {})

        for f in sorted(files):
            full = root / f
            manifest[str(rel_dir).replace('\\', '/')][full.name] = full

    component_groups = collections.defaultdict(list)

    # Now emit a <Fragment> for each directory.
    # Each directory is composed of a <DirectoryRef> pointing to its parent
    # and defines child <Directory>'s and a <Component> with all the files.
    for dir_name, entries in sorted(manifest.items()):
        # The directory id is derived from the path. But the root directory
        # is special.
        if dir_name == '.':
            parent_directory_id = 'INSTALLDIR'
        else:
            parent_directory_id = 'hg.dir.%s' % dir_name.replace('/', '.')

        fragment = doc.createElement('Fragment')
        directory_ref = doc.createElement('DirectoryRef')
        directory_ref.setAttribute('Id', parent_directory_id)

        # Add <Directory> entries for immediate children directories.
        for possible_child in sorted(manifest.keys()):
            if (
                dir_name == '.'
                and '/' not in possible_child
                and possible_child != '.'
            ):
                child_directory_id = 'hg.dir.%s' % possible_child
                name = possible_child
            else:
                if not possible_child.startswith('%s/' % dir_name):
                    continue
                name = possible_child[len(dir_name) + 1 :]
                if '/' in name:
                    continue

                child_directory_id = 'hg.dir.%s' % possible_child.replace(
                    '/', '.'
                )

            directory = doc.createElement('Directory')
            directory.setAttribute('Id', child_directory_id)
            directory.setAttribute('Name', name)
            directory_ref.appendChild(directory)

        # Add <Component>s for files in this directory.
        for rel, source_path in sorted(entries.items()):
            if dir_name == '.':
                full_rel = rel
            else:
                full_rel = '%s/%s' % (dir_name, rel)

            component_unique_id = (
                'https://www.mercurial-scm.org/wix-installer/0/component/%s'
                % full_rel
            )
            component_guid = uuid.uuid5(uuid.NAMESPACE_URL, component_unique_id)
            component_id = 'hg.component.%s' % str(component_guid).replace(
                '-', '_'
            )

            component = doc.createElement('Component')

            component.setAttribute('Id', component_id)
            component.setAttribute('Guid', str(component_guid).upper())
            component.setAttribute('Win64', 'yes' if is_x64 else 'no')

            # Assign this component to a top-level group.
            if dir_name == '.':
                component_groups['ROOT'].append(component_id)
            elif '/' in dir_name:
                component_groups[dir_name[0 : dir_name.index('/')]].append(
                    component_id
                )
            else:
                component_groups[dir_name].append(component_id)

            unique_id = (
                'https://www.mercurial-scm.org/wix-installer/0/%s' % full_rel
            )
            file_guid = uuid.uuid5(uuid.NAMESPACE_URL, unique_id)

            # IDs have length limits. So use GUID to derive them.
            file_guid_normalized = str(file_guid).replace('-', '_')
            file_id = 'hg.file.%s' % file_guid_normalized

            file_element = doc.createElement('File')
            file_element.setAttribute('Id', file_id)
            file_element.setAttribute('Source', str(source_path))
            file_element.setAttribute('KeyPath', 'yes')
            file_element.setAttribute('ReadOnly', 'yes')

            component.appendChild(file_element)
            directory_ref.appendChild(component)

        fragment.appendChild(directory_ref)
        doc.documentElement.appendChild(fragment)

    for group, component_ids in sorted(component_groups.items()):
        fragment = doc.createElement('Fragment')
        component_group = doc.createElement('ComponentGroup')
        component_group.setAttribute('Id', 'hg.group.%s' % group)

        for component_id in component_ids:
            component_ref = doc.createElement('ComponentRef')
            component_ref.setAttribute('Id', component_id)
            component_group.appendChild(component_ref)

        fragment.appendChild(component_group)
        doc.documentElement.appendChild(fragment)

    # Add <Shortcut> to files that have it defined.
    for file_id, metadata in sorted(SHORTCUTS.items()):
        els = doc.getElementsByTagName('File')
        els = [el for el in els if el.getAttribute('Id') == file_id]

        if not els:
            raise Exception('could not find File[Id=%s]' % file_id)

        for el in els:
            shortcut = doc.createElement('Shortcut')
            shortcut.setAttribute('Id', 'hg.shortcut.%s' % file_id)
            shortcut.setAttribute('Directory', 'ProgramMenuDir')
            shortcut.setAttribute('Icon', 'hgIcon.ico')
            shortcut.setAttribute('IconIndex', '0')
            shortcut.setAttribute('Advertise', 'yes')
            for k, v in sorted(metadata.items()):
                shortcut.setAttribute(k, v)

            el.appendChild(shortcut)

    return doc.toprettyxml()


def build_installer(
    source_dir: pathlib.Path,
    python_exe: pathlib.Path,
    msi_name='mercurial',
    version=None,
    post_build_fn=None,
    extra_packages_script=None,
    extra_wxs: typing.Optional[typing.Dict[str, str]] = None,
    extra_features: typing.Optional[typing.List[str]] = None,
):
    """Build a WiX MSI installer.

    ``source_dir`` is the path to the Mercurial source tree to use.
    ``arch`` is the target architecture. either ``x86`` or ``x64``.
    ``python_exe`` is the path to the Python executable to use/bundle.
    ``version`` is the Mercurial version string. If not defined,
    ``mercurial/__version__.py`` will be consulted.
    ``post_build_fn`` is a callable that will be called after building
    Mercurial but before invoking WiX. It can be used to e.g. facilitate
    signing. It is passed the paths to the Mercurial source, build, and
    dist directories and the resolved Mercurial version.
    ``extra_packages_script`` is a command to be run to inject extra packages
    into the py2exe binary. It should stage packages into the virtualenv and
    print a null byte followed by a newline-separated list of packages that
    should be included in the exe.
    ``extra_wxs`` is a dict of {wxs_name: working_dir_for_wxs_build}.
    ``extra_features`` is a list of additional named Features to include in
    the build. These must match Feature names in one of the wxs scripts.
    """
    arch = 'x64' if r'\x64' in os.environ.get('LIB', '') else 'x86'

    hg_build_dir = source_dir / 'build'
    dist_dir = source_dir / 'dist'
    wix_dir = source_dir / 'contrib' / 'packaging' / 'wix'

    requirements_txt = (
        source_dir / 'contrib' / 'packaging' / 'requirements_win32.txt'
    )

    build_py2exe(
        source_dir,
        hg_build_dir,
        python_exe,
        'wix',
        requirements_txt,
        extra_packages=EXTRA_PACKAGES,
        extra_packages_script=extra_packages_script,
    )

    orig_version = version or find_version(source_dir)
    version = normalize_windows_version(orig_version)
    print('using version string: %s' % version)
    if version != orig_version:
        print('(normalized from: %s)' % orig_version)

    if post_build_fn:
        post_build_fn(source_dir, hg_build_dir, dist_dir, version)

    build_dir = hg_build_dir / ('wix-%s' % arch)
    staging_dir = build_dir / 'stage'

    build_dir.mkdir(exist_ok=True)

    # Purge the staging directory for every build so packaging is pristine.
    if staging_dir.exists():
        print('purging %s' % staging_dir)
        shutil.rmtree(staging_dir)

    stage_install(source_dir, staging_dir, lower_case=True)

    # We also install some extra files.
    process_install_rules(EXTRA_INSTALL_RULES, source_dir, staging_dir)

    # And remove some files we don't want.
    for f in STAGING_REMOVE_FILES:
        p = staging_dir / f
        if p.exists():
            print('removing %s' % p)
            p.unlink()

    wix_pkg, wix_entry = download_entry('wix', hg_build_dir)
    wix_path = hg_build_dir / ('wix-%s' % wix_entry['version'])

    if not wix_path.exists():
        extract_zip_to_directory(wix_pkg, wix_path)

    ensure_vc90_merge_modules(hg_build_dir)

    source_build_rel = pathlib.Path(os.path.relpath(source_dir, build_dir))

    defines = {'Platform': arch}

    # Derive a .wxs file with the staged files.
    manifest_wxs = build_dir / 'stage.wxs'
    with manifest_wxs.open('w', encoding='utf-8') as fh:
        fh.write(make_files_xml(staging_dir, is_x64=arch == 'x64'))

    run_candle(wix_path, build_dir, manifest_wxs, staging_dir, defines=defines)

    for source, rel_path in sorted((extra_wxs or {}).items()):
        run_candle(wix_path, build_dir, source, rel_path, defines=defines)

    source = wix_dir / 'mercurial.wxs'
    defines['Version'] = version
    defines['Comments'] = 'Installs Mercurial version %s' % version
    defines['VCRedistSrcDir'] = str(hg_build_dir)
    if extra_features:
        assert all(';' not in f for f in extra_features)
        defines['MercurialExtraFeatures'] = ';'.join(extra_features)

    run_candle(wix_path, build_dir, source, source_build_rel, defines=defines)

    msi_path = (
        source_dir / 'dist' / ('%s-%s-%s.msi' % (msi_name, orig_version, arch))
    )

    args = [
        str(wix_path / 'light.exe'),
        '-nologo',
        '-ext',
        'WixUIExtension',
        '-sw1076',
        '-spdb',
        '-o',
        str(msi_path),
    ]

    for source, rel_path in sorted((extra_wxs or {}).items()):
        assert source.endswith('.wxs')
        source = os.path.basename(source)
        args.append(str(build_dir / ('%s.wixobj' % source[:-4])))

    args.extend(
        [str(build_dir / 'stage.wixobj'), str(build_dir / 'mercurial.wixobj'),]
    )

    subprocess.run(args, cwd=str(source_dir), check=True)

    print('%s created' % msi_path)

    return {
        'msi_path': msi_path,
    }


def build_signed_installer(
    source_dir: pathlib.Path,
    python_exe: pathlib.Path,
    name: str,
    version=None,
    subject_name=None,
    cert_path=None,
    cert_password=None,
    timestamp_url=None,
    extra_packages_script=None,
    extra_wxs=None,
    extra_features=None,
):
    """Build an installer with signed executables."""

    post_build_fn = make_post_build_signing_fn(
        name,
        subject_name=subject_name,
        cert_path=cert_path,
        cert_password=cert_password,
        timestamp_url=timestamp_url,
    )

    info = build_installer(
        source_dir,
        python_exe=python_exe,
        msi_name=name.lower(),
        version=version,
        post_build_fn=post_build_fn,
        extra_packages_script=extra_packages_script,
        extra_wxs=extra_wxs,
        extra_features=extra_features,
    )

    description = '%s %s' % (name, version)

    sign_with_signtool(
        info['msi_path'],
        description,
        subject_name=subject_name,
        cert_path=cert_path,
        cert_password=cert_password,
        timestamp_url=timestamp_url,
    )
