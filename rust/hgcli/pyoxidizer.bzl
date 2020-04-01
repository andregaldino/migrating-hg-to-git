ROOT = CWD + "/../.."

def make_exe():
    dist = default_python_distribution()

    code = "import hgdemandimport; hgdemandimport.enable(); from mercurial import dispatch; dispatch.run()"

    config = PythonInterpreterConfig(
        raw_allocator = "system",
        run_eval = code,
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

    exe.add_python_resources(dist.pip_install([ROOT]))

    return exe

def make_install(exe):
    m = FileManifest()

    # `hg` goes in root directory.
    m.add_python_resource(".", exe)

    templates = glob(
        include = [ROOT + "/mercurial/templates/**/*"],
        strip_prefix = ROOT + "/mercurial/",
    )
    m.add_manifest(templates)

    return m

def make_embedded_resources(exe):
    return exe.to_embedded_resources()

register_target("exe", make_exe)
register_target("app", make_install, depends = ["exe"], default = True)
register_target("embedded", make_embedded_resources, depends = ["exe"], default_build_script = True)
resolve_targets()

# END OF COMMON USER-ADJUSTED SETTINGS.
#
# Everything below this is typically managed by PyOxidizer and doesn't need
# to be updated by people.

PYOXIDIZER_VERSION = "0.7.0-pre"
PYOXIDIZER_COMMIT = "c772a1379c3026314eda1c8ea244b86c0658951d"
