ROOT = CWD + "/../.."

IS_WINDOWS = "windows" in BUILD_TARGET_TRIPLE

# Code to run in Python interpreter.
RUN_CODE = "import hgdemandimport; hgdemandimport.enable(); from mercurial import dispatch; dispatch.run()"

set_build_path(ROOT + "/build/pyoxidizer")

def make_distribution():
    return default_python_distribution()

def make_distribution_windows():
    return default_python_distribution(flavor = "standalone_dynamic")

def resource_callback(policy, resource):
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
    packaging_policy.resources_location_fallback = "filesystem-relative:lib"
    packaging_policy.register_resource_callback(resource_callback)

    config = dist.make_python_interpreter_config()
    config.raw_allocator = "system"
    config.run_mode = "eval:%s" % RUN_CODE
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
            exe.pip_install(["-r", ROOT + "/contrib/packaging/requirements-windows-py2.txt"]),
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

PYOXIDIZER_VERSION = "0.9.0"
PYOXIDIZER_COMMIT = "1fbc264cc004226cd76ee452e0a386ffca6ccfb1"
