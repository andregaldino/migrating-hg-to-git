ROOT = CWD + "/../.."

# Code to run in Python interpreter.
RUN_CODE = "import hgdemandimport; hgdemandimport.enable(); from mercurial import dispatch; dispatch.run()"

set_build_path(ROOT + "/build/pyoxidizer")

def make_distribution():
    return default_python_distribution()

def make_distribution_windows():
    return default_python_distribution(flavor = "standalone_dynamic")

def make_exe(dist):
    """Builds a Rust-wrapped Mercurial binary."""
    config = PythonInterpreterConfig(
        raw_allocator = "system",
        run_eval = RUN_CODE,
        # We want to let the user load extensions from the file system
        filesystem_importer = True,
        # We need this to make resourceutil happy, since it looks for sys.frozen.
        sys_frozen = True,
        legacy_windows_stdio = True,
    )

    exe = dist.to_python_executable(
        name = "hg",
        resources_policy = "prefer-in-memory-fallback-filesystem-relative:lib",
        config = config,
        # Extension may depend on any Python functionality. Include all
        # extensions.
        extension_module_filter = "all",
    )

    # Add Mercurial to resources.
    for resource in dist.pip_install(["--verbose", ROOT]):
        # This is a bit wonky and worth explaining.
        #
        # Various parts of Mercurial don't yet support loading package
        # resources via the ResourceReader interface. Or, not having
        # file-based resources would be too inconvenient for users.
        #
        # So, for package resources, we package them both in the
        # filesystem as well as in memory. If both are defined,
        # PyOxidizer will prefer the in-memory location. So even
        # if the filesystem file isn't packaged in the location
        # specified here, we should never encounter an errors as the
        # resource will always be available in memory.
        if type(resource) == "PythonPackageResource":
            exe.add_filesystem_relative_python_resource(".", resource)
            exe.add_in_memory_python_resource(resource)
        else:
            exe.add_python_resource(resource)

    # On Windows, we install extra packages for convenience.
    if "windows" in BUILD_TARGET_TRIPLE:
        exe.add_python_resources(
            dist.pip_install(["-r", ROOT + "/contrib/packaging/requirements_win32.txt"]),
        )

    return exe

def make_manifest(dist, exe):
    m = FileManifest()
    m.add_python_resource(".", exe)

    return m

def make_embedded_resources(exe):
    return exe.to_embedded_resources()

register_target("distribution_posix", make_distribution)
register_target("distribution_windows", make_distribution_windows)

register_target("exe_posix", make_exe, depends = ["distribution_posix"])
register_target("exe_windows", make_exe, depends = ["distribution_windows"])

register_target(
    "app_posix",
    make_manifest,
    depends = ["distribution_posix", "exe_posix"],
    default = "windows" not in BUILD_TARGET_TRIPLE,
)
register_target(
    "app_windows",
    make_manifest,
    depends = ["distribution_windows", "exe_windows"],
    default = "windows" in BUILD_TARGET_TRIPLE,
)

resolve_targets()

# END OF COMMON USER-ADJUSTED SETTINGS.
#
# Everything below this is typically managed by PyOxidizer and doesn't need
# to be updated by people.

PYOXIDIZER_VERSION = "0.7.0"
