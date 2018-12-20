#include "pyutil.h"

#include <string>

namespace contrib
{

static char cpypath[8192] = "\0";

static PyObject *mainmod;
static PyObject *globals;

/* TODO: use Python 3 for this fuzzing? */
PyMODINIT_FUNC initparsers(void);

void initpy(const char *cselfpath)
{
	const std::string subdir = "/sanpy/lib/python2.7";
	/* HACK ALERT: we need a full Python installation built without
	   pymalloc and with ASAN, so we dump one in
	   $OUT/sanpy/lib/python2.7. This helps us wire that up. */
	std::string selfpath(cselfpath);
	std::string pypath;
	auto pos = selfpath.rfind("/");
	if (pos == std::string::npos) {
		char wd[8192];
		getcwd(wd, 8192);
		pypath = std::string(wd) + subdir;
	} else {
		pypath = selfpath.substr(0, pos) + subdir;
	}
	strncpy(cpypath, pypath.c_str(), pypath.size());
	setenv("PYTHONPATH", cpypath, 1);
	setenv("PYTHONNOUSERSITE", "1", 1);
	/* prevent Python from looking up users in the fuzz environment */
	setenv("PYTHONUSERBASE", cpypath, 1);
	Py_SetPythonHome(cpypath);
	Py_InitializeEx(0);
	mainmod = PyImport_AddModule("__main__");
	globals = PyModule_GetDict(mainmod);
	initparsers();
}

PyObject *pyglobals()
{
	return globals;
}

} // namespace contrib
