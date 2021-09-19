/*
 exewrapper.c - wrapper for calling a python script on Windows

 Copyright 2012 Adrian Buehlmann <adrian@cadifra.com> and others

 This software may be used and distributed according to the terms of the
 GNU General Public License version 2 or any later version.
*/

#include <Python.h>
#include <stdio.h>
#include <tchar.h>
#include <windows.h>

#include "hgpythonlib.h"

#ifdef __GNUC__
int strcat_s(char *d, size_t n, const char *s)
{
	return !strncat(d, s, n);
}
int strcpy_s(char *d, size_t n, const char *s)
{
	return !strncpy(d, s, n);
}

#define _tcscpy_s strcpy_s
#define _tcscat_s strcat_s
#define _countof(array) (sizeof(array) / sizeof(array[0]))
#endif

#if PY_MAJOR_VERSION >= 3

#pragma comment(lib, "Advapi32.lib")

/* python.org installations */
#define CORE_PATH L"SOFTWARE\\Python\\PythonCore"

/* Microsoft Store installations */
#define LOOKASIDE_PATH                                                         \
	L"SOFTWARE\\Microsoft\\AppModel\\Lookaside\\user\\Software\\Python\\"  \
	L"PythonCore"

static wchar_t *_locate_python_for_key(HKEY root, LPCWSTR subkey, size_t *size)
{
	wchar_t installPathKey[512];
	wchar_t *executable = NULL;
	DWORD type;
	DWORD sz = 0;
	HKEY ip_key;
	LSTATUS status;

	_snwprintf_s(installPathKey, sizeof(installPathKey), _TRUNCATE,
	             L"%ls\\%d.%d\\InstallPath", subkey, PY_MAJOR_VERSION,
	             PY_MINOR_VERSION);

	status =
	    RegOpenKeyExW(root, installPathKey, 0, KEY_QUERY_VALUE, &ip_key);

	if (status != ERROR_SUCCESS)
		return NULL;

	status = RegQueryValueExW(ip_key, L"ExecutablePath", NULL, &type,
	                          (LPBYTE)executable, &sz);
	if (status == ERROR_SUCCESS) {
		/* Allocate extra space so path\to\python.exe can be converted
		 * to path\to\python39.dll + NUL.
		 */
		*size = sz + sizeof(_T(HGPYTHONLIB ".dll")) + sizeof(wchar_t);
		executable = malloc(*size);

		if (executable) {
			status =
			    RegQueryValueExW(ip_key, L"ExecutablePath", NULL,
			                     &type, (LPBYTE)executable, &sz);

			if (status != ERROR_SUCCESS) {
				free(executable);
				executable = NULL;
			} else {
				/* Not all values are stored NUL terminated */
				executable[sz] = L'\0';
			}
		}
	}

	RegCloseKey(ip_key);
	return executable;
}

static HMODULE load_system_py3(void)
{
	wchar_t *subkeys[] = {CORE_PATH, LOOKASIDE_PATH};
	HKEY roots[] = {HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER};

	/* Give priority to python.org installs, because MS Store installs can
	 * break with user profile corruption, and also use some NTFS feature
	 * that MSYS doesn't understand.
	 */
	for (int s = 0; s < _countof(subkeys); s++) {
		for (int r = 0; r < _countof(roots); r++) {
			size_t size = 0;
			wchar_t *py =
			    _locate_python_for_key(roots[r], subkeys[s], &size);
			wchar_t *cut = NULL;
			HMODULE pydll;

			if (!py) {
				continue;
			}

			/* Cut off the python executable component */
			cut = wcsrchr(py, L'\\');
			if (cut == NULL) {
				free(py);
				continue;
			}
			*cut = 0;

			wcscat_s(py, size, _T("\\" HGPYTHONLIB ".dll"));

			pydll = LoadLibrary(py);

			/* Also load python3.dll, so we don't pick up a random
			 * one on PATH. We don't search {sys.prefix}\DLLs like
			 * python.exe because this is commented as "not been a
			 * normal install layout for a while", and don't search
			 * LOAD_LIBRARY_SEARCH_APPLICATION_DIR because it's not
			 * clear what the use case is.
			 */
			if (pydll != NULL) {
				HANDLE py3dll = NULL;

				*cut = 0;
				wcscat_s(py, size, L"\\python3.dll");

				py3dll = LoadLibrary(py);
				if (py3dll == NULL) {
					const char *err;
					err = "failed to load python3.dll "
					      "for " HGPYTHONLIB ".dll";
					fprintf(stderr, "abort: %s (0x%X)\n",
					        err, GetLastError());
					exit(255);
				}
			}

			free(py);

			if (pydll != NULL) {
				return pydll;
			}
		}
	}

	return NULL;
}
#endif

static TCHAR pyscript[MAX_PATH + 10];
static TCHAR pyhome[MAX_PATH + 10];
static TCHAR pydllfile[MAX_PATH + 10];

int _tmain(int argc, TCHAR *argv[])
{
	TCHAR *p;
	int ret;
	int i;
	int n;
	TCHAR **pyargv;
	WIN32_FIND_DATA fdata;
	HANDLE hfind;
	const char *err;
	HMODULE pydll;
	void(__cdecl * Py_SetPythonHome)(TCHAR * home);
	int(__cdecl * Py_Main)(int argc, TCHAR *argv[]);

#if PY_MAJOR_VERSION >= 3
	_wputenv(L"PYTHONLEGACYWINDOWSSTDIO=1");
#endif

	if (GetModuleFileName(NULL, pyscript, _countof(pyscript)) == 0) {
		err = "GetModuleFileName failed";
		goto bail;
	}

	p = _tcsrchr(pyscript, '.');
	if (p == NULL) {
		err = "malformed module filename";
		goto bail;
	}
	*p = 0; /* cut trailing ".exe" */
	_tcscpy_s(pyhome, _countof(pyhome), pyscript);

	hfind = FindFirstFile(pyscript, &fdata);
	if (hfind != INVALID_HANDLE_VALUE) {
		/* pyscript exists, close handle */
		FindClose(hfind);
	} else {
		/* file pyscript isn't there, take <pyscript>exe.py */
		_tcscat_s(pyscript, _countof(pyscript), _T("exe.py"));
	}

	pydll = NULL;

	p = _tcsrchr(pyhome, _T('\\'));
	if (p == NULL) {
		err = "can't find backslash in module filename";
		goto bail;
	}
	*p = 0; /* cut at directory */

	/* check for private Python of HackableMercurial */
	_tcscat_s(pyhome, _countof(pyhome), _T("\\hg-python"));

	hfind = FindFirstFile(pyhome, &fdata);
	if (hfind != INVALID_HANDLE_VALUE) {
		/* Path .\hg-python exists. We are probably in HackableMercurial
		scenario, so let's load python dll from this dir. */
		FindClose(hfind);
		_tcscpy_s(pydllfile, _countof(pydllfile), pyhome);
		_tcscat_s(pydllfile, _countof(pydllfile),
		          _T("\\") _T(HGPYTHONLIB) _T(".dll"));
		pydll = LoadLibrary(pydllfile);
		if (pydll == NULL) {
			err = "failed to load private Python DLL " HGPYTHONLIB
			      ".dll";
			goto bail;
		}
		Py_SetPythonHome =
		    (void *)GetProcAddress(pydll, "Py_SetPythonHome");
		if (Py_SetPythonHome == NULL) {
			err = "failed to get Py_SetPythonHome";
			goto bail;
		}
		Py_SetPythonHome(pyhome);
	}

#if PY_MAJOR_VERSION >= 3
	if (pydll == NULL) {
		pydll = load_system_py3();
	}
#endif

	if (pydll == NULL) {
		pydll = LoadLibrary(_T(HGPYTHONLIB) _T(".dll"));
		if (pydll == NULL) {
			err = "failed to load Python DLL " HGPYTHONLIB ".dll";
			goto bail;
		}
	}

	Py_Main = (void *)GetProcAddress(pydll, "Py_Main");
	if (Py_Main == NULL) {
		err = "failed to get Py_Main";
		goto bail;
	}

	/*
	Only add the pyscript to the args, if it's not already there. It may
	already be there, if the script spawned a child process of itself, in
	the same way as it got called, that is, with the pyscript already in
	place. So we optionally accept the pyscript as the first argument
	(argv[1]), letting our exe taking the role of the python interpreter.
	*/
	if (argc >= 2 && _tcscmp(argv[1], pyscript) == 0) {
		/*
		pyscript is already in the args, so there is no need to copy
		the args and we can directly call the python interpreter with
		the original args.
		*/
		return Py_Main(argc, argv);
	}

	/*
	Start assembling the args for the Python interpreter call. We put the
	name of our exe (argv[0]) in the position where the python.exe
	canonically is, and insert the pyscript next.
	*/
	pyargv = malloc((argc + 5) * sizeof(TCHAR *));
	if (pyargv == NULL) {
		err = "not enough memory";
		goto bail;
	}
	n = 0;
	pyargv[n++] = argv[0];
	pyargv[n++] = pyscript;

	/* copy remaining args from the command line */
	for (i = 1; i < argc; i++)
		pyargv[n++] = argv[i];
	/* argv[argc] is guaranteed to be NULL, so we forward that guarantee */
	pyargv[n] = NULL;

	ret = Py_Main(n, pyargv); /* The Python interpreter call */

	free(pyargv);
	return ret;

bail:
	fprintf(stderr, "abort: %s\n", err);
	return 255;
}
