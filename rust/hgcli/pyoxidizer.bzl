ROOT = CWD + "/../.."

IS_WINDOWS = "windows" in BUILD_TARGET_TRIPLE

# Code to run in Python interpreter.
RUN_CODE = "import hgdemandimport; hgdemandimport.enable(); from mercurial import dispatch; dispatch.run()"

set_build_path(ROOT + "/build/pyoxidizer")

def make_distribution():
    return default_python_distribution(python_version = "3.8")

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
    config.raw_allocator = "system"
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

    return exe

def make_manifest(dist, exe):
    m = FileManifest()
    m.add_python_resource(".", exe)

    return m

register_target("distribution", make_distribution)
register_target("exe", make_exe, depends = ["distribution"])
register_target("app", make_manifest, depends = ["distribution", "exe"], default = True)

resolve_targets()
