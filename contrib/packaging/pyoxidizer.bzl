# Instructions:
#
# 1. cargo install --version 0.5.0 pyoxidizer
# 2. cd /path/to/hg
# 3. pyoxidizer build --path contrib/packaging [--release]
# 4. Run build/pyoxidizer/<arch>/<debug|release>/app/hg
#
# If you need to build again, you need to remove the build/lib.* and
# build/temp.* directories, otherwise PyOxidizer fails to pick up C
# extensions. This is a bug in PyOxidizer.

ROOT = CWD + "/../.."

set_build_path(ROOT + "/build/pyoxidizer")

def make_exe():
    dist = default_python_distribution()

    code = "import hgdemandimport; hgdemandimport.enable(); from mercurial import dispatch; dispatch.run()"

    config = PythonInterpreterConfig(
        raw_allocator = "system",
        run_eval = code,
        # We need this to make resourceutil happy, since it looks for sys.frozen.
        sys_frozen = True,
        legacy_windows_stdio = True,
    )

    exe = dist.to_python_executable(
        name = "hg",
        config = config,
    )

    # Use setup.py install to build Mercurial and collect Python resources to
    # embed in the executable.
    resources = dist.setup_py_install(ROOT)
    exe.add_python_resources(resources)

    return exe

def make_install(exe):
    m = FileManifest()

    # `hg` goes in root directory.
    m.add_python_resource(".", exe)

    templates = glob(
        include=[ROOT + "/mercurial/templates/**/*"],
        strip_prefix = ROOT + "/mercurial/",
    )
    m.add_manifest(templates)

    return m

register_target("exe", make_exe)
register_target("app", make_install, depends = ["exe"], default = True)

resolve_targets()
