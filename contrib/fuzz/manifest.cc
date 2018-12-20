#include <Python.h>
#include <assert.h>
#include <stdlib.h>
#include <unistd.h>

#include "pyutil.h"

#include <string>

extern "C" {

static PyCodeObject *code;

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	contrib::initpy(*argv[0]);
	code = (PyCodeObject *)Py_CompileString(R"py(
from parsers import lazymanifest
try:
  lm = lazymanifest(mdata)
  # iterate the whole thing, which causes the code to fully parse
  # every line in the manifest
  list(lm.iterentries())
  lm[b'xyzzy'] = (b'\0' * 20, 'x')
  # do an insert, text should change
  assert lm.text() != mdata, "insert should change text and didn't: %r %r" % (lm.text(), mdata)
  del lm[b'xyzzy']
  # should be back to the same
  assert lm.text() == mdata, "delete should have restored text but didn't: %r %r" % (lm.text(), mdata)
except Exception as e:
  pass
  # uncomment this print if you're editing this Python code
  # to debug failures.
  # print e
)py",
	                                        "fuzzer", Py_file_input);
	return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
	PyObject *mtext =
	    PyBytes_FromStringAndSize((const char *)Data, (Py_ssize_t)Size);
	PyObject *locals = PyDict_New();
	PyDict_SetItemString(locals, "mdata", mtext);
	PyObject *res = PyEval_EvalCode(code, contrib::pyglobals(), locals);
	if (!res) {
		PyErr_Print();
	}
	Py_XDECREF(res);
	Py_DECREF(locals);
	Py_DECREF(mtext);
	return 0; // Non-zero return values are reserved for future use.
}
}
