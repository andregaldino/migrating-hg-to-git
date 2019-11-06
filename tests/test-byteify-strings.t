#require py37

  $ byteify_strings () {
  >   "$PYTHON" "$TESTDIR/../contrib/byteify-strings.py" "$@"
  > }

Test version

  $ byteify_strings --version
  Byteify strings * (glob)

Test in-place

  $ cat > testfile.py <<EOF
  > obj['test'] = b"1234"
  > mydict.iteritems()
  > EOF
  $ byteify_strings testfile.py -i
  $ cat testfile.py
  obj[b'test'] = b"1234"
  mydict.iteritems()

Test with dictiter

  $ cat > testfile.py <<EOF
  > obj['test'] = b"1234"
  > mydict.iteritems()
  > EOF
  $ byteify_strings testfile.py --dictiter
  obj[b'test'] = b"1234"
  mydict.items()

Test kwargs-like objects

  $ cat > testfile.py <<EOF
  > kwargs['test'] = "123"
  > kwargs[test['testing']]
  > kwargs[test[[['testing']]]]
  > kwargs[kwargs['testing']]
  > kwargs.get('test')
  > kwargs.pop('test')
  > kwargs.get('test', 'testing')
  > kwargs.pop('test', 'testing')
  > kwargs.setdefault('test', 'testing')
  > 
  > opts['test'] = "123"
  > opts[test['testing']]
  > opts[test[[['testing']]]]
  > opts[opts['testing']]
  > opts.get('test')
  > opts.pop('test')
  > opts.get('test', 'testing')
  > opts.pop('test', 'testing')
  > opts.setdefault('test', 'testing')
  > 
  > commitopts['test'] = "123"
  > commitopts[test['testing']]
  > commitopts[test[[['testing']]]]
  > commitopts[commitopts['testing']]
  > commitopts.get('test')
  > commitopts.pop('test')
  > commitopts.get('test', 'testing')
  > commitopts.pop('test', 'testing')
  > commitopts.setdefault('test', 'testing')
  > EOF
  $ byteify_strings testfile.py --treat-as-kwargs kwargs opts commitopts
  kwargs['test'] = b"123"
  kwargs[test[b'testing']]
  kwargs[test[[[b'testing']]]]
  kwargs[kwargs['testing']]
  kwargs.get('test')
  kwargs.pop('test')
  kwargs.get('test', b'testing')
  kwargs.pop('test', b'testing')
  kwargs.setdefault('test', b'testing')
  
  opts['test'] = b"123"
  opts[test[b'testing']]
  opts[test[[[b'testing']]]]
  opts[opts['testing']]
  opts.get('test')
  opts.pop('test')
  opts.get('test', b'testing')
  opts.pop('test', b'testing')
  opts.setdefault('test', b'testing')
  
  commitopts['test'] = b"123"
  commitopts[test[b'testing']]
  commitopts[test[[[b'testing']]]]
  commitopts[commitopts['testing']]
  commitopts.get('test')
  commitopts.pop('test')
  commitopts.get('test', b'testing')
  commitopts.pop('test', b'testing')
  commitopts.setdefault('test', b'testing')

Test attr*() as methods

  $ cat > testfile.py <<EOF
  > setattr(o, 'a', 1)
  > util.setattr(o, 'ae', 1)
  > util.getattr(o, 'alksjdf', 'default')
  > util.addattr(o, 'asdf')
  > util.hasattr(o, 'lksjdf', 'default')
  > util.safehasattr(o, 'lksjdf', 'default')
  > @eh.wrapfunction(func, 'lksjdf')
  > def f():
  >     pass
  > @eh.wrapclass(klass, 'lksjdf')
  > def f():
  >     pass
  > EOF
  $ byteify_strings testfile.py --allow-attr-methods
  setattr(o, 'a', 1)
  util.setattr(o, 'ae', 1)
  util.getattr(o, 'alksjdf', b'default')
  util.addattr(o, 'asdf')
  util.hasattr(o, 'lksjdf', b'default')
  util.safehasattr(o, 'lksjdf', b'default')
  @eh.wrapfunction(func, 'lksjdf')
  def f():
      pass
  @eh.wrapclass(klass, 'lksjdf')
  def f():
      pass

Test without attr*() as methods

  $ cat > testfile.py <<EOF
  > setattr(o, 'a', 1)
  > util.setattr(o, 'ae', 1)
  > util.getattr(o, 'alksjdf', 'default')
  > util.addattr(o, 'asdf')
  > util.hasattr(o, 'lksjdf', 'default')
  > util.safehasattr(o, 'lksjdf', 'default')
  > @eh.wrapfunction(func, 'lksjdf')
  > def f():
  >     pass
  > @eh.wrapclass(klass, 'lksjdf')
  > def f():
  >     pass
  > EOF
  $ byteify_strings testfile.py
  setattr(o, 'a', 1)
  util.setattr(o, b'ae', 1)
  util.getattr(o, b'alksjdf', b'default')
  util.addattr(o, b'asdf')
  util.hasattr(o, b'lksjdf', b'default')
  util.safehasattr(o, b'lksjdf', b'default')
  @eh.wrapfunction(func, b'lksjdf')
  def f():
      pass
  @eh.wrapclass(klass, b'lksjdf')
  def f():
      pass

Test ignore comments

  $ cat > testfile.py <<EOF
  > # py3-transform: off
  > "none"
  > "of"
  > 'these'
  > s = """should"""
  > d = '''be'''
  > # py3-transform: on
  > "this should"
  > 'and this also'
  > 
  > # no-py3-transform
  > l = "this should be ignored"
  > l2 = "this shouldn't"
  > 
  > EOF
  $ byteify_strings testfile.py
  # py3-transform: off
  "none"
  "of"
  'these'
  s = """should"""
  d = '''be'''
  # py3-transform: on
  b"this should"
  b'and this also'
  
  # no-py3-transform
  l = "this should be ignored"
  l2 = b"this shouldn't"
  
Test triple-quoted strings

  $ cat > testfile.py <<EOF
  > """This is ignored
  > """
  > 
  > line = """
  >   This should not be
  > """
  > line = '''
  > Neither should this
  > '''
  > EOF
  $ byteify_strings testfile.py
  """This is ignored
  """
  
  line = b"""
    This should not be
  """
  line = b'''
  Neither should this
  '''

Test prefixed strings

  $ cat > testfile.py <<EOF
  > obj['test'] = b"1234"
  > obj[r'test'] = u"1234"
  > EOF
  $ byteify_strings testfile.py
  obj[b'test'] = b"1234"
  obj[r'test'] = u"1234"

Test multi-line alignment

  $ cat > testfile.py <<'EOF'
  > def foo():
  >     error.Abort(_("foo"
  >                  "bar"
  >                  "%s")
  >                % parameter)
  > {
  >     'test': dict,
  >     'test2': dict,
  > }
  > [
  >    "thing",
  >    "thing2"
  > ]
  > (
  >    "tuple",
  >    "tuple2",
  > )
  > {"thing",
  >  }
  > EOF
  $ byteify_strings testfile.py
  def foo():
      error.Abort(_(b"foo"
                    b"bar"
                    b"%s")
                  % parameter)
  {
      b'test': dict,
      b'test2': dict,
  }
  [
     b"thing",
     b"thing2"
  ]
  (
     b"tuple",
     b"tuple2",
  )
  {b"thing",
   }
