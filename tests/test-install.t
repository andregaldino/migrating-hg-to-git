hg debuginstall
  $ hg debuginstall
  checking encoding (ascii)...
  checking Python executable (*) (glob)
  checking Python version (2.*) (glob)
  checking Python lib (*lib*)... (glob)
  checking Python security support (*) (glob)
    TLS 1.2 not supported by Python install; network connections lack modern security (?)
    SNI not supported by Python install; may have connectivity issues with some servers (?)
  checking Mercurial version (*) (glob)
  checking Mercurial custom build (*) (glob)
  checking module policy (*) (glob)
  checking installed modules (*mercurial)... (glob)
  checking registered compression engines (*zlib*) (glob)
  checking available compression engines (*zlib*) (glob)
  checking available compression engines for wire protocol (*zlib*) (glob)
  checking templates (*mercurial?templates)... (glob)
  checking default template (*mercurial?templates?map-cmdline.default) (glob)
  checking commit editor... (* -c "import sys; sys.exit(0)") (glob)
  checking username (test)
  no problems detected

hg debuginstall JSON
  $ hg debuginstall -Tjson | sed 's|\\\\|\\|g'
  [
   {
    "compengines": ["bz2", "bz2truncated", "none", "zlib"*], (glob)
    "compenginesavail": ["bz2", "bz2truncated", "none", "zlib"*], (glob)
    "compenginesserver": [*"zlib"*], (glob)
    "defaulttemplate": "*mercurial?templates?map-cmdline.default", (glob)
    "defaulttemplateerror": null,
    "defaulttemplatenotfound": "default",
    "editor": "* -c \"import sys; sys.exit(0)\"", (glob)
    "editornotfound": false,
    "encoding": "ascii",
    "encodingerror": null,
    "extensionserror": null,
    "hgmodulepolicy": "*", (glob)
    "hgmodules": "*mercurial", (glob)
    "hgver": "*", (glob)
    "hgverextra": "*", (glob)
    "problems": 0,
    "pythonexe": "*", (glob)
    "pythonlib": "*", (glob)
    "pythonsecurity": [*], (glob)
    "pythonver": "*.*.*", (glob)
    "templatedirs": "*mercurial?templates", (glob)
    "username": "test",
    "usernameerror": null,
    "vinotfound": false
   }
  ]

hg debuginstall with no username
  $ HGUSER= hg debuginstall
  checking encoding (ascii)...
  checking Python executable (*) (glob)
  checking Python version (2.*) (glob)
  checking Python lib (*lib*)... (glob)
  checking Python security support (*) (glob)
    TLS 1.2 not supported by Python install; network connections lack modern security (?)
    SNI not supported by Python install; may have connectivity issues with some servers (?)
  checking Mercurial version (*) (glob)
  checking Mercurial custom build (*) (glob)
  checking module policy (*) (glob)
  checking installed modules (*mercurial)... (glob)
  checking registered compression engines (*zlib*) (glob)
  checking available compression engines (*zlib*) (glob)
  checking available compression engines for wire protocol (*zlib*) (glob)
  checking templates (*mercurial?templates)... (glob)
  checking default template (*mercurial?templates?map-cmdline.default) (glob)
  checking commit editor... (* -c "import sys; sys.exit(0)") (glob)
  checking username...
   no username supplied
   (specify a username in your configuration file)
  1 problems detected, please check your install!
  [1]

path variables are expanded (~ is the same as $TESTTMP)
  $ mkdir tools
  $ touch tools/testeditor.exe
#if execbit
  $ chmod 755 tools/testeditor.exe
#endif
  $ hg debuginstall --config ui.editor=~/tools/testeditor.exe
  checking encoding (ascii)...
  checking Python executable (*) (glob)
  checking Python version (*) (glob)
  checking Python lib (*lib*)... (glob)
  checking Python security support (*) (glob)
    TLS 1.2 not supported by Python install; network connections lack modern security (?)
    SNI not supported by Python install; may have connectivity issues with some servers (?)
  checking Mercurial version (*) (glob)
  checking Mercurial custom build (*) (glob)
  checking module policy (*) (glob)
  checking installed modules (*mercurial)... (glob)
  checking registered compression engines (*zlib*) (glob)
  checking available compression engines (*zlib*) (glob)
  checking available compression engines for wire protocol (*zlib*) (glob)
  checking templates (*mercurial?templates)... (glob)
  checking default template (*mercurial?templates?map-cmdline.default) (glob)
  checking commit editor... (* -c "import sys; sys.exit(0)") (glob)
  checking username (test)
  no problems detected

#if test-repo
  $ . "$TESTDIR/helpers-testrepo.sh"

  $ cat >> wixxml.py << EOF
  > import os, subprocess, sys
  > import xml.etree.ElementTree as ET
  > 
  > # MSYS mangles the path if it expands $TESTDIR
  > testdir = os.environ['TESTDIR']
  > ns = {'wix' : 'http://schemas.microsoft.com/wix/2006/wi'}
  > 
  > def directory(node, relpath):
  >     '''generator of files in the xml node, rooted at relpath'''
  >     dirs = node.findall('./{%(wix)s}Directory' % ns)
  > 
  >     for d in dirs:
  >         for subfile in directory(d, relpath + d.attrib['Name'] + '/'):
  >             yield subfile
  > 
  >     files = node.findall('./{%(wix)s}Component/{%(wix)s}File' % ns)
  > 
  >     for f in files:
  >         yield relpath + f.attrib['Name']
  > 
  > def hgdirectory(relpath):
  >     '''generator of tracked files, rooted at relpath'''
  >     hgdir = "%s/../mercurial" % (testdir)
  >     args = ['hg', '--cwd', hgdir, 'files', relpath]
  >     proc = subprocess.Popen(args, stdout=subprocess.PIPE,
  >                             stderr=subprocess.PIPE)
  >     output = proc.communicate()[0]
  > 
  >     slash = '/'
  >     for line in output.splitlines():
  >         if os.name == 'nt':
  >             yield line.replace(os.sep, slash)
  >         else:
  >             yield line
  > 
  > tracked = [f for f in hgdirectory(sys.argv[1])]
  > 
  > xml = ET.parse("%s/../contrib/wix/%s.wxs" % (testdir, sys.argv[1]))
  > root = xml.getroot()
  > dir = root.find('.//{%(wix)s}DirectoryRef' % ns)
  > 
  > installed = [f for f in directory(dir, '')]
  > 
  > print('Not installed:')
  > for f in sorted(set(tracked) - set(installed)):
  >     print('  %s' % f)
  > 
  > print('Not tracked:')
  > for f in sorted(set(installed) - set(tracked)):
  >     print('  %s' % f)
  > EOF

  $ python wixxml.py help
  Not installed:
    help/common.txt
    help/hg-ssh.8.txt
    help/hg.1.txt
    help/hgignore.5.txt
    help/hgrc.5.txt
    help/pager.txt
  Not tracked:

  $ python wixxml.py templates
  Not installed:
  Not tracked:

#endif
