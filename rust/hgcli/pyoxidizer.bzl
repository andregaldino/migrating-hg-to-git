# The following variables can be passed in as parameters:
#
# VERSION
#   Version string of program being produced.
#
# MSI_NAME
#   Root name of MSI installer.
#
# EXTRA_MSI_FEATURES
#   ; delimited string of extra features to advertise in the built MSA.
#
# SIGNING_PFX_PATH
#   Path to code signing certificate to use.
#
# SIGNING_PFX_PASSWORD
#   Password to code signing PFX file defined by SIGNING_PFX_PATH.
#
# SIGNING_SUBJECT_NAME
#   String fragment in code signing certificate subject name used to find
#   code signing certificate in Windows certificate store.
#
# TIME_STAMP_SERVER_URL
#   URL of time-stamp token authority (RFC 3161) servers to stamp code signatures.

ROOT = CWD + "/../.."

VERSION = VARS.get("VERSION", "5.8")
MSI_NAME = VARS.get("MSI_NAME", "mercurial")
EXTRA_MSI_FEATURES = VARS.get("EXTRA_MSI_FEATURES")
SIGNING_PFX_PATH = VARS.get("SIGNING_PFX_PATH")
SIGNING_PFX_PASSWORD = VARS.get("SIGNING_PFX_PASSWORD", "")
SIGNING_SUBJECT_NAME = VARS.get("SIGNING_SUBJECT_NAME")
TIME_STAMP_SERVER_URL = VARS.get("TIME_STAMP_SERVER_URL", "http://timestamp.digicert.com")

IS_WINDOWS = "windows" in BUILD_TARGET_TRIPLE

# Code to run in Python interpreter.
RUN_CODE = "import hgdemandimport; hgdemandimport.enable(); from mercurial import dispatch; dispatch.run()"

set_build_path(ROOT + "/build/pyoxidizer")

def make_distribution():
    return default_python_distribution(python_version = "3.9")

def resource_callback(policy, resource):
    if not IS_WINDOWS:
        resource.add_location = "in-memory"
        return

    # We use a custom resource routing policy to influence where things are loaded
    # from.
    #
    # For Python modules and resources, we load from memory if they are in
    # the standard library and from the filesystem if not. This is because
    # parts of Mercurial and some 3rd party packages aren't yet compatible
    # with memory loading.
    #
    # For Python extension modules, we load from the filesystem because
    # this yields greatest compatibility.
    if type(resource) in ("PythonModuleSource", "PythonPackageResource", "PythonPackageDistributionResource"):
        if resource.is_stdlib:
            resource.add_location = "in-memory"
        else:
            resource.add_location = "filesystem-relative:lib"

    elif type(resource) == "PythonExtensionModule":
        resource.add_location = "filesystem-relative:lib"

def make_exe(dist):
    """Builds a Rust-wrapped Mercurial binary."""
    packaging_policy = dist.make_python_packaging_policy()

    # Extension may depend on any Python functionality. Include all
    # extensions.
    packaging_policy.extension_module_filter = "all"
    packaging_policy.resources_location = "in-memory"
    if IS_WINDOWS:
        packaging_policy.resources_location_fallback = "filesystem-relative:lib"
    packaging_policy.register_resource_callback(resource_callback)

    config = dist.make_python_interpreter_config()
    config.allocator_backend = "default"
    config.run_command = RUN_CODE

    # We want to let the user load extensions from the file system
    config.filesystem_importer = True

    # We need this to make resourceutil happy, since it looks for sys.frozen.
    config.sys_frozen = True
    config.legacy_windows_stdio = True

    exe = dist.to_python_executable(
        name = "hg",
        packaging_policy = packaging_policy,
        config = config,
    )

    # Add Mercurial to resources.
    exe.add_python_resources(exe.pip_install(["--verbose", ROOT]))

    # On Windows, we install extra packages for convenience.
    if IS_WINDOWS:
        exe.add_python_resources(
            exe.pip_install(["-r", ROOT + "/contrib/packaging/requirements-windows-py3.txt"]),
        )
    extra_packages = VARS.get("extra_py_packages", "")
    if extra_packages:
        for extra in extra_packages.split(","):
            extra_src, pkgs = extra.split("=")
            pkgs = pkgs.split(":")
            exe.add_python_resources(exe.read_package_root(extra_src, pkgs))

    return exe

def make_manifest(dist, exe):
    m = FileManifest()
    m.add_python_resource(".", exe)

    return m


# This adjusts the InstallManifest produced from exe generation to provide
# additional files found in a Windows install layout.
def make_windows_install_layout(manifest):
    # Copy various files to new install locations. This can go away once
    # we're using the importlib resource reader.
    RECURSIVE_COPIES = {
        "lib/mercurial/locale/": "locale/",
        "lib/mercurial/templates/": "templates/",
    }
    for (search, replace) in RECURSIVE_COPIES.items():
        for path in manifest.paths():
            if path.startswith(search):
                new_path = path.replace(search, replace)
                print("copy %s to %s" % (path, new_path))
                file = manifest.get_file(path)
                manifest.add_file(file, path = new_path)

    # Similar to above, but with filename pattern matching.
    # lib/mercurial/helptext/**/*.txt -> helptext/
    # lib/mercurial/defaultrc/*.rc -> defaultrc/
    for path in manifest.paths():
        if path.startswith("lib/mercurial/helptext/") and path.endswith(".txt"):
            new_path = path[len("lib/mercurial/"):]
        elif path.startswith("lib/mercurial/defaultrc/") and path.endswith(".rc"):
            new_path = path[len("lib/mercurial/"):]
        else:
            continue

        print("copying %s to %s" % (path, new_path))
        manifest.add_file(manifest.get_file(path), path = new_path)

    extra_install_files = VARS.get("extra_install_files", "")
    if extra_install_files:
        for extra in extra_install_files.split(","):
            print("adding extra files from %s" % extra)
            # TODO: I expected a ** glob to work, but it didn't.
            #
            # TODO: I know this has forward-slash paths. As far as I can tell,
            # backslashes don't ever match glob() expansions in 
            # tugger-starlark, even on Windows.
            manifest.add_manifest(glob(include=[extra + "/*/*"], strip_prefix=extra+"/"))

    # We also install a handful of additional files.
    EXTRA_CONTRIB_FILES = [
        "bash_completion",
        "hgweb.fcgi",
        "hgweb.wsgi",
        "logo-droplets.svg",
        "mercurial.el",
        "mq.el",
        "tcsh_completion",
        "tcsh_completion_build.sh",
        "xml.rnc",
        "zsh_completion",
    ]

    for f in EXTRA_CONTRIB_FILES:
        manifest.add_file(FileContent(path = ROOT + "/contrib/" + f), directory = "contrib")

    # Individual files with full source to destination path mapping.
    EXTRA_FILES = {
        "contrib/hgk": "contrib/hgk.tcl",
        "contrib/win32/postinstall.txt": "ReleaseNotes.txt",
        "contrib/win32/ReadMe.html": "ReadMe.html",
        "doc/style.css": "doc/style.css",
        "COPYING": "Copying.txt",
    }

    for source, dest in EXTRA_FILES.items():
        print("adding extra file %s" % dest)
        manifest.add_file(FileContent(path = ROOT + "/" + source), path = dest)

    # And finally some wildcard matches.
    manifest.add_manifest(glob(
        include = [ROOT + "/contrib/vim/*"],
        strip_prefix = ROOT + "/"
    ))
    manifest.add_manifest(glob(
        include = [ROOT + "/doc/*.html"],
        strip_prefix = ROOT + "/"
    ))

    # But we don't ship hg-ssh on Windows, so exclude its documentation.
    manifest.remove("doc/hg-ssh.8.html")

    return manifest


def make_msi(manifest):
    manifest = make_windows_install_layout(manifest)

    if "x86_64" in BUILD_TARGET_TRIPLE:
        platform = "x64"
    else:
        platform = "x86"

    manifest.add_file(
        FileContent(path = ROOT + "/contrib/packaging/wix/COPYING.rtf"),
        path = "COPYING.rtf",
    )
    manifest.remove("Copying.txt")
    manifest.add_file(
        FileContent(path = ROOT + "/contrib/win32/mercurial.ini"),
        path = "defaultrc/mercurial.rc",
    )
    manifest.add_file(
        FileContent(filename = "editor.rc", content = "[ui]\neditor = notepad\n"),
        path = "defaultrc/editor.rc",
    )

    wix = WiXInstaller("hg", "%s-%s.msi" % (MSI_NAME, VERSION))

    # Materialize files in the manifest to the install layout.
    wix.add_install_files(manifest)

    # From mercurial.wxs.
    wix.install_files_root_directory_id = "INSTALLDIR"

    # Pull in our custom .wxs files.
    defines = {
        "PyOxidizer": "1",
        "Platform": platform,
        "Version": VERSION,
        "Comments": "Installs Mercurial version %s" % VERSION,
        "PythonVersion": "3",
        "MercurialHasLib": "1",
    }

    if EXTRA_MSI_FEATURES:
        defines["MercurialExtraFeatures"] = EXTRA_MSI_FEATURES

    wix.add_wxs_file(
        ROOT + "/contrib/packaging/wix/mercurial.wxs",
        preprocessor_parameters=defines,
    )

    # Our .wxs references to other files. Pull those into the build environment.
    for f in ("defines.wxi", "guids.wxi", "COPYING.rtf"):
        wix.add_build_file(f, ROOT + "/contrib/packaging/wix/" + f)

    wix.add_build_file("mercurial.ico", ROOT + "/contrib/win32/mercurial.ico")

    return wix


def register_code_signers():
    if not IS_WINDOWS:
        return

    if SIGNING_PFX_PATH:
        signer = code_signer_from_pfx_file(SIGNING_PFX_PATH, SIGNING_PFX_PASSWORD)
    elif SIGNING_SUBJECT_NAME:
        signer = code_signer_from_windows_store_subject(SIGNING_SUBJECT_NAME)
    else:
        signer = None

    if signer:
        signer.set_time_stamp_server(TIME_STAMP_SERVER_URL)
        signer.activate()


register_code_signers()

register_target("distribution", make_distribution)
register_target("exe", make_exe, depends = ["distribution"])
register_target("app", make_manifest, depends = ["distribution", "exe"], default = True)
register_target("msi", make_msi, depends = ["app"])

resolve_targets()
