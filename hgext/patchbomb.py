# patchbomb.py - sending Mercurial changesets as patch emails
#
#  Copyright 2005-2009 Matt Mackall <mpm@selenic.com> and others
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

'''command to send changesets as (a series of) patch emails

The series is started off with a "[PATCH 0 of N]" introduction, which
describes the series as a whole.

Each patch email has a Subject line of "[PATCH M of N] ...", using the
first line of the changeset description as the subject text. The
message contains two or three body parts:

- The changeset description.
- [Optional] The result of running diffstat on the patch.
- The patch itself, as generated by :hg:`export`.

Each message refers to the first in the series using the In-Reply-To
and References headers, so they will show up as a sequence in threaded
mail and news readers, and in mail archives.

To configure other defaults, add a section like this to your
configuration file::

  [email]
  from = My Name <my@email>
  to = recipient1, recipient2, ...
  cc = cc1, cc2, ...
  bcc = bcc1, bcc2, ...
  reply-to = address1, address2, ...

Use ``[patchbomb]`` as configuration section name if you need to
override global ``[email]`` address settings.

Then you can use the :hg:`email` command to mail a series of
changesets as a patchbomb.

You can also either configure the method option in the email section
to be a sendmail compatible mailer or fill out the [smtp] section so
that the patchbomb extension can automatically send patchbombs
directly from the commandline. See the [email] and [smtp] sections in
hgrc(5) for details.

By default, :hg:`email` will prompt for a ``To`` or ``CC`` header if
you do not supply one via configuration or the command line.  You can
override this to never prompt by configuring an empty value::

  [email]
  cc =

You can control the default inclusion of an introduction message with the
``patchbomb.intro`` configuration option. The configuration is always
overwritten by command line flags like --intro and --desc::

  [patchbomb]
  intro=auto   # include introduction message if more than 1 patch (default)
  intro=never  # never include an introduction message
  intro=always # always include an introduction message

You can specify a template for flags to be added in subject prefixes. Flags
specified by --flag option are exported as ``{flags}`` keyword::

  [patchbomb]
  flagtemplate = "{separate(' ',
                            ifeq(branch, 'default', '', branch|upper),
                            flags)}"

You can set patchbomb to always ask for confirmation by setting
``patchbomb.confirm`` to true.
'''
from __future__ import absolute_import

import email.encoders as emailencoders
import email.generator as emailgen
import email.mime.base as emimebase
import email.mime.multipart as emimemultipart
import email.utils as eutil
import errno
import os
import socket

from mercurial.i18n import _
from mercurial import (
    cmdutil,
    commands,
    encoding,
    error,
    formatter,
    hg,
    mail,
    node as nodemod,
    patch,
    pycompat,
    registrar,
    scmutil,
    templater,
    util,
)
from mercurial.utils import dateutil
stringio = util.stringio

cmdtable = {}
command = registrar.command(cmdtable)

configtable = {}
configitem = registrar.configitem(configtable)

configitem('patchbomb', 'bundletype',
    default=None,
)
configitem('patchbomb', 'bcc',
    default=None,
)
configitem('patchbomb', 'cc',
    default=None,
)
configitem('patchbomb', 'confirm',
    default=False,
)
configitem('patchbomb', 'flagtemplate',
    default=None,
)
configitem('patchbomb', 'from',
    default=None,
)
configitem('patchbomb', 'intro',
    default='auto',
)
configitem('patchbomb', 'publicurl',
    default=None,
)
configitem('patchbomb', 'reply-to',
    default=None,
)
configitem('patchbomb', 'to',
    default=None,
)

if pycompat.ispy3:
    _bytesgenerator = emailgen.BytesGenerator
else:
    _bytesgenerator = emailgen.Generator

# Note for extension authors: ONLY specify testedwith = 'ships-with-hg-core' for
# extensions which SHIP WITH MERCURIAL. Non-mainline extensions should
# be specifying the version(s) of Mercurial they are tested with, or
# leave the attribute unspecified.
testedwith = 'ships-with-hg-core'

def _addpullheader(seq, ctx):
    """Add a header pointing to a public URL where the changeset is available
    """
    repo = ctx.repo()
    # experimental config: patchbomb.publicurl
    # waiting for some logic that check that the changeset are available on the
    # destination before patchbombing anything.
    publicurl = repo.ui.config('patchbomb', 'publicurl')
    if publicurl:
        return ('Available At %s\n'
                '#              hg pull %s -r %s' % (publicurl, publicurl, ctx))
    return None

def uisetup(ui):
    cmdutil.extraexport.append('pullurl')
    cmdutil.extraexportmap['pullurl'] = _addpullheader

def reposetup(ui, repo):
    if not repo.local():
        return
    repo._wlockfreeprefix.add('last-email.txt')

def prompt(ui, prompt, default=None, rest=':'):
    if default:
        prompt += ' [%s]' % default
    return ui.prompt(prompt + rest, default)

def introwanted(ui, opts, number):
    '''is an introductory message apparently wanted?'''
    introconfig = ui.config('patchbomb', 'intro')
    if opts.get('intro') or opts.get('desc'):
        intro = True
    elif introconfig == 'always':
        intro = True
    elif introconfig == 'never':
        intro = False
    elif introconfig == 'auto':
        intro = 1 < number
    else:
        ui.write_err(_('warning: invalid patchbomb.intro value "%s"\n')
                     % introconfig)
        ui.write_err(_('(should be one of always, never, auto)\n'))
        intro = 1 < number
    return intro

def _formatflags(ui, repo, rev, flags):
    """build flag string optionally by template"""
    tmpl = ui.config('patchbomb', 'flagtemplate')
    if not tmpl:
        return ' '.join(flags)
    out = util.stringio()
    opts = {'template': templater.unquotestring(tmpl)}
    with formatter.templateformatter(ui, out, 'patchbombflag', opts) as fm:
        fm.startitem()
        fm.context(ctx=repo[rev])
        fm.write('flags', '%s', fm.formatlist(flags, name='flag'))
    return out.getvalue()

def _formatprefix(ui, repo, rev, flags, idx, total, numbered):
    """build prefix to patch subject"""
    flag = _formatflags(ui, repo, rev, flags)
    if flag:
        flag = ' ' + flag

    if not numbered:
        return '[PATCH%s]' % flag
    else:
        tlen = len("%d" % total)
        return '[PATCH %0*d of %d%s]' % (tlen, idx, total, flag)

def makepatch(ui, repo, rev, patchlines, opts, _charsets, idx, total, numbered,
              patchname=None):

    desc = []
    node = None
    body = ''

    for line in patchlines:
        if line.startswith('#'):
            if line.startswith('# Node ID'):
                node = line.split()[-1]
            continue
        if line.startswith('diff -r') or line.startswith('diff --git'):
            break
        desc.append(line)

    if not patchname and not node:
        raise ValueError

    if opts.get('attach') and not opts.get('body'):
        body = ('\n'.join(desc[1:]).strip() or
                'Patch subject is complete summary.')
        body += '\n\n\n'

    if opts.get('plain'):
        while patchlines and patchlines[0].startswith('# '):
            patchlines.pop(0)
        if patchlines:
            patchlines.pop(0)
        while patchlines and not patchlines[0].strip():
            patchlines.pop(0)

    ds = patch.diffstat(patchlines)
    if opts.get('diffstat'):
        body += ds + '\n\n'

    addattachment = opts.get('attach') or opts.get('inline')
    if not addattachment or opts.get('body'):
        body += '\n'.join(patchlines)

    if addattachment:
        msg = emimemultipart.MIMEMultipart()
        if body:
            msg.attach(mail.mimeencode(ui, body, _charsets, opts.get('test')))
        p = mail.mimetextpatch('\n'.join(patchlines), 'x-patch',
                               opts.get('test'))
        binnode = nodemod.bin(node)
        # if node is mq patch, it will have the patch file's name as a tag
        if not patchname:
            patchtags = [t for t in repo.nodetags(binnode)
                         if t.endswith('.patch') or t.endswith('.diff')]
            if patchtags:
                patchname = patchtags[0]
            elif total > 1:
                patchname = cmdutil.makefilename(repo[node], '%b-%n.patch',
                                                 seqno=idx, total=total)
            else:
                patchname = cmdutil.makefilename(repo[node], '%b.patch')
        disposition = r'inline'
        if opts.get('attach'):
            disposition = r'attachment'
        p[r'Content-Disposition'] = (
            disposition + r'; filename=' + encoding.strfromlocal(patchname))
        msg.attach(p)
    else:
        msg = mail.mimetextpatch(body, display=opts.get('test'))

    prefix = _formatprefix(ui, repo, rev, opts.get('flag'), idx, total,
                           numbered)
    subj = desc[0].strip().rstrip('. ')
    if not numbered:
        subj = ' '.join([prefix, opts.get('subject') or subj])
    else:
        subj = ' '.join([prefix, subj])
    msg['Subject'] = mail.headencode(ui, subj, _charsets, opts.get('test'))
    msg['X-Mercurial-Node'] = node
    msg['X-Mercurial-Series-Index'] = '%i' % idx
    msg['X-Mercurial-Series-Total'] = '%i' % total
    return msg, subj, ds

def _getpatches(repo, revs, **opts):
    """return a list of patches for a list of revisions

    Each patch in the list is itself a list of lines.
    """
    ui = repo.ui
    prev = repo['.'].rev()
    for r in revs:
        if r == prev and (repo[None].files() or repo[None].deleted()):
            ui.warn(_('warning: working directory has '
                      'uncommitted changes\n'))
        output = stringio()
        cmdutil.exportfile(repo, [r], output,
                           opts=patch.difffeatureopts(ui, opts, git=True))
        yield output.getvalue().split('\n')
def _getbundle(repo, dest, **opts):
    """return a bundle containing changesets missing in "dest"

    The `opts` keyword-arguments are the same as the one accepted by the
    `bundle` command.

    The bundle is a returned as a single in-memory binary blob.
    """
    ui = repo.ui
    tmpdir = pycompat.mkdtemp(prefix='hg-email-bundle-')
    tmpfn = os.path.join(tmpdir, 'bundle')
    btype = ui.config('patchbomb', 'bundletype')
    if btype:
        opts[r'type'] = btype
    try:
        commands.bundle(ui, repo, tmpfn, dest, **opts)
        return util.readfile(tmpfn)
    finally:
        try:
            os.unlink(tmpfn)
        except OSError:
            pass
        os.rmdir(tmpdir)

def _getdescription(repo, defaultbody, sender, **opts):
    """obtain the body of the introduction message and return it

    This is also used for the body of email with an attached bundle.

    The body can be obtained either from the command line option or entered by
    the user through the editor.
    """
    ui = repo.ui
    if opts.get(r'desc'):
        body = open(opts.get(r'desc')).read()
    else:
        ui.write(_('\nWrite the introductory message for the '
                   'patch series.\n\n'))
        body = ui.edit(defaultbody, sender, repopath=repo.path,
                       action='patchbombbody')
        # Save series description in case sendmail fails
        msgfile = repo.vfs('last-email.txt', 'wb')
        msgfile.write(body)
        msgfile.close()
    return body

def _getbundlemsgs(repo, sender, bundle, **opts):
    """Get the full email for sending a given bundle

    This function returns a list of "email" tuples (subject, content, None).
    The list is always one message long in that case.
    """
    ui = repo.ui
    _charsets = mail._charsets(ui)
    subj = (opts.get(r'subject')
            or prompt(ui, 'Subject:', 'A bundle for your repository'))

    body = _getdescription(repo, '', sender, **opts)
    msg = emimemultipart.MIMEMultipart()
    if body:
        msg.attach(mail.mimeencode(ui, body, _charsets, opts.get(r'test')))
    datapart = emimebase.MIMEBase(r'application', r'x-mercurial-bundle')
    datapart.set_payload(bundle)
    bundlename = '%s.hg' % opts.get(r'bundlename', 'bundle')
    datapart.add_header(r'Content-Disposition', r'attachment',
                        filename=encoding.strfromlocal(bundlename))
    emailencoders.encode_base64(datapart)
    msg.attach(datapart)
    msg['Subject'] = mail.headencode(ui, subj, _charsets, opts.get(r'test'))
    return [(msg, subj, None)]

def _makeintro(repo, sender, revs, patches, **opts):
    """make an introduction email, asking the user for content if needed

    email is returned as (subject, body, cumulative-diffstat)"""
    ui = repo.ui
    _charsets = mail._charsets(ui)

    # use the last revision which is likely to be a bookmarked head
    prefix = _formatprefix(ui, repo, revs.last(), opts.get(r'flag'),
                           0, len(patches), numbered=True)
    subj = (opts.get(r'subject') or
            prompt(ui, '(optional) Subject: ', rest=prefix, default=''))
    if not subj:
        return None         # skip intro if the user doesn't bother

    subj = prefix + ' ' + subj

    body = ''
    if opts.get(r'diffstat'):
        # generate a cumulative diffstat of the whole patch series
        diffstat = patch.diffstat(sum(patches, []))
        body = '\n' + diffstat
    else:
        diffstat = None

    body = _getdescription(repo, body, sender, **opts)
    msg = mail.mimeencode(ui, body, _charsets, opts.get(r'test'))
    msg['Subject'] = mail.headencode(ui, subj, _charsets,
                                     opts.get(r'test'))
    return (msg, subj, diffstat)

def _getpatchmsgs(repo, sender, revs, patchnames=None, **opts):
    """return a list of emails from a list of patches

    This involves introduction message creation if necessary.

    This function returns a list of "email" tuples (subject, content, None).
    """
    bytesopts = pycompat.byteskwargs(opts)
    ui = repo.ui
    _charsets = mail._charsets(ui)
    patches = list(_getpatches(repo, revs, **opts))
    msgs = []

    ui.write(_('this patch series consists of %d patches.\n\n')
             % len(patches))

    # build the intro message, or skip it if the user declines
    if introwanted(ui, bytesopts, len(patches)):
        msg = _makeintro(repo, sender, revs, patches, **opts)
        if msg:
            msgs.append(msg)

    # are we going to send more than one message?
    numbered = len(msgs) + len(patches) > 1

    # now generate the actual patch messages
    name = None
    assert len(revs) == len(patches)
    for i, (r, p) in enumerate(zip(revs, patches)):
        if patchnames:
            name = patchnames[i]
        msg = makepatch(ui, repo, r, p, bytesopts, _charsets,
                        i + 1, len(patches), numbered, name)
        msgs.append(msg)

    return msgs

def _getoutgoing(repo, dest, revs):
    '''Return the revisions present locally but not in dest'''
    ui = repo.ui
    url = ui.expandpath(dest or 'default-push', dest or 'default')
    url = hg.parseurl(url)[0]
    ui.status(_('comparing with %s\n') % util.hidepassword(url))

    revs = [r for r in revs if r >= 0]
    if not revs:
        revs = [repo.changelog.tiprev()]
    revs = repo.revs('outgoing(%s) and ::%ld', dest or '', revs)
    if not revs:
        ui.status(_("no changes found\n"))
    return revs

def _msgid(node, timestamp):
    return '<%s.%d@%s>' % (node, timestamp,
                           encoding.strtolocal(socket.getfqdn()))

emailopts = [
    ('', 'body', None, _('send patches as inline message text (default)')),
    ('a', 'attach', None, _('send patches as attachments')),
    ('i', 'inline', None, _('send patches as inline attachments')),
    ('', 'bcc', [], _('email addresses of blind carbon copy recipients')),
    ('c', 'cc', [], _('email addresses of copy recipients')),
    ('', 'confirm', None, _('ask for confirmation before sending')),
    ('d', 'diffstat', None, _('add diffstat output to messages')),
    ('', 'date', '', _('use the given date as the sending date')),
    ('', 'desc', '', _('use the given file as the series description')),
    ('f', 'from', '', _('email address of sender')),
    ('n', 'test', None, _('print messages that would be sent')),
    ('m', 'mbox', '', _('write messages to mbox file instead of sending them')),
    ('', 'reply-to', [], _('email addresses replies should be sent to')),
    ('s', 'subject', '', _('subject of first message (intro or single patch)')),
    ('', 'in-reply-to', '', _('message identifier to reply to')),
    ('', 'flag', [], _('flags to add in subject prefixes')),
    ('t', 'to', [], _('email addresses of recipients'))]

@command('email',
    [('g', 'git', None, _('use git extended diff format')),
    ('', 'plain', None, _('omit hg patch header')),
    ('o', 'outgoing', None,
     _('send changes not found in the target repository')),
    ('b', 'bundle', None, _('send changes not in target as a binary bundle')),
    ('B', 'bookmark', '', _('send changes only reachable by given bookmark')),
    ('', 'bundlename', 'bundle',
     _('name of the bundle attachment file'), _('NAME')),
    ('r', 'rev', [], _('a revision to send'), _('REV')),
    ('', 'force', None, _('run even when remote repository is unrelated '
       '(with -b/--bundle)')),
    ('', 'base', [], _('a base changeset to specify instead of a destination '
       '(with -b/--bundle)'), _('REV')),
    ('', 'intro', None, _('send an introduction email for a single patch')),
    ] + emailopts + cmdutil.remoteopts,
    _('hg email [OPTION]... [DEST]...'))
def email(ui, repo, *revs, **opts):
    '''send changesets by email

    By default, diffs are sent in the format generated by
    :hg:`export`, one per message. The series starts with a "[PATCH 0
    of N]" introduction, which describes the series as a whole.

    Each patch email has a Subject line of "[PATCH M of N] ...", using
    the first line of the changeset description as the subject text.
    The message contains two or three parts. First, the changeset
    description.

    With the -d/--diffstat option, if the diffstat program is
    installed, the result of running diffstat on the patch is inserted.

    Finally, the patch itself, as generated by :hg:`export`.

    With the -d/--diffstat or --confirm options, you will be presented
    with a final summary of all messages and asked for confirmation before
    the messages are sent.

    By default the patch is included as text in the email body for
    easy reviewing. Using the -a/--attach option will instead create
    an attachment for the patch. With -i/--inline an inline attachment
    will be created. You can include a patch both as text in the email
    body and as a regular or an inline attachment by combining the
    -a/--attach or -i/--inline with the --body option.

    With -B/--bookmark changesets reachable by the given bookmark are
    selected.

    With -o/--outgoing, emails will be generated for patches not found
    in the destination repository (or only those which are ancestors
    of the specified revisions if any are provided)

    With -b/--bundle, changesets are selected as for --outgoing, but a
    single email containing a binary Mercurial bundle as an attachment
    will be sent. Use the ``patchbomb.bundletype`` config option to
    control the bundle type as with :hg:`bundle --type`.

    With -m/--mbox, instead of previewing each patchbomb message in a
    pager or sending the messages directly, it will create a UNIX
    mailbox file with the patch emails. This mailbox file can be
    previewed with any mail user agent which supports UNIX mbox
    files.

    With -n/--test, all steps will run, but mail will not be sent.
    You will be prompted for an email recipient address, a subject and
    an introductory message describing the patches of your patchbomb.
    Then when all is done, patchbomb messages are displayed.

    In case email sending fails, you will find a backup of your series
    introductory message in ``.hg/last-email.txt``.

    The default behavior of this command can be customized through
    configuration. (See :hg:`help patchbomb` for details)

    Examples::

      hg email -r 3000          # send patch 3000 only
      hg email -r 3000 -r 3001  # send patches 3000 and 3001
      hg email -r 3000:3005     # send patches 3000 through 3005
      hg email 3000             # send patch 3000 (deprecated)

      hg email -o               # send all patches not in default
      hg email -o DEST          # send all patches not in DEST
      hg email -o -r 3000       # send all ancestors of 3000 not in default
      hg email -o -r 3000 DEST  # send all ancestors of 3000 not in DEST

      hg email -B feature       # send all ancestors of feature bookmark

      hg email -b               # send bundle of all patches not in default
      hg email -b DEST          # send bundle of all patches not in DEST
      hg email -b -r 3000       # bundle of all ancestors of 3000 not in default
      hg email -b -r 3000 DEST  # bundle of all ancestors of 3000 not in DEST

      hg email -o -m mbox &&    # generate an mbox file...
        mutt -R -f mbox         # ... and view it with mutt
      hg email -o -m mbox &&    # generate an mbox file ...
        formail -s sendmail \\   # ... and use formail to send from the mbox
          -bm -t < mbox         # ... using sendmail

    Before using this command, you will need to enable email in your
    hgrc. See the [email] section in hgrc(5) for details.
    '''
    opts = pycompat.byteskwargs(opts)

    _charsets = mail._charsets(ui)

    bundle = opts.get('bundle')
    date = opts.get('date')
    mbox = opts.get('mbox')
    outgoing = opts.get('outgoing')
    rev = opts.get('rev')
    bookmark = opts.get('bookmark')

    if not (opts.get('test') or mbox):
        # really sending
        mail.validateconfig(ui)

    if not (revs or rev or outgoing or bundle or bookmark):
        raise error.Abort(_('specify at least one changeset with -B, -r or -o'))

    if outgoing and bundle:
        raise error.Abort(_("--outgoing mode always on with --bundle;"
                           " do not re-specify --outgoing"))
    if rev and bookmark:
        raise error.Abort(_("-r and -B are mutually exclusive"))

    if outgoing or bundle:
        if len(revs) > 1:
            raise error.Abort(_("too many destinations"))
        if revs:
            dest = revs[0]
        else:
            dest = None
        revs = []

    if rev:
        if revs:
            raise error.Abort(_('use only one form to specify the revision'))
        revs = rev
    elif bookmark:
        if bookmark not in repo._bookmarks:
            raise error.Abort(_("bookmark '%s' not found") % bookmark)
        revs = scmutil.bookmarkrevs(repo, bookmark)

    revs = scmutil.revrange(repo, revs)
    if outgoing:
        revs = _getoutgoing(repo, dest, revs)
    if bundle:
        opts['revs'] = ["%d" % r for r in revs]

    # check if revision exist on the public destination
    publicurl = repo.ui.config('patchbomb', 'publicurl')
    if publicurl:
        repo.ui.debug('checking that revision exist in the public repo\n')
        try:
            publicpeer = hg.peer(repo, {}, publicurl)
        except error.RepoError:
            repo.ui.write_err(_('unable to access public repo: %s\n')
                              % publicurl)
            raise
        if not publicpeer.capable('known'):
            repo.ui.debug('skipping existence checks: public repo too old\n')
        else:
            out = [repo[r] for r in revs]
            known = publicpeer.known(h.node() for h in out)
            missing = []
            for idx, h in enumerate(out):
                if not known[idx]:
                    missing.append(h)
            if missing:
                if 1 < len(missing):
                    msg = _('public "%s" is missing %s and %i others')
                    msg %= (publicurl, missing[0], len(missing) - 1)
                else:
                    msg = _('public url %s is missing %s')
                    msg %= (publicurl, missing[0])
                missingrevs = [ctx.rev() for ctx in missing]
                revhint = ' '.join('-r %s' % h
                                   for h in repo.set('heads(%ld)', missingrevs))
                hint = _("use 'hg push %s %s'") % (publicurl, revhint)
                raise error.Abort(msg, hint=hint)

    # start
    if date:
        start_time = dateutil.parsedate(date)
    else:
        start_time = dateutil.makedate()

    def genmsgid(id):
        return _msgid(id[:20], int(start_time[0]))

    # deprecated config: patchbomb.from
    sender = (opts.get('from') or ui.config('email', 'from') or
              ui.config('patchbomb', 'from') or
              prompt(ui, 'From', ui.username()))

    if bundle:
        stropts = pycompat.strkwargs(opts)
        bundledata = _getbundle(repo, dest, **stropts)
        bundleopts = stropts.copy()
        bundleopts.pop(r'bundle', None)  # already processed
        msgs = _getbundlemsgs(repo, sender, bundledata, **bundleopts)
    else:
        msgs = _getpatchmsgs(repo, sender, revs, **pycompat.strkwargs(opts))

    showaddrs = []

    def getaddrs(header, ask=False, default=None):
        configkey = header.lower()
        opt = header.replace('-', '_').lower()
        addrs = opts.get(opt)
        if addrs:
            showaddrs.append('%s: %s' % (header, ', '.join(addrs)))
            return mail.addrlistencode(ui, addrs, _charsets, opts.get('test'))

        # not on the command line: fallback to config and then maybe ask
        addr = (ui.config('email', configkey) or
                ui.config('patchbomb', configkey))
        if not addr:
            specified = (ui.hasconfig('email', configkey) or
                         ui.hasconfig('patchbomb', configkey))
            if not specified and ask:
                addr = prompt(ui, header, default=default)
        if addr:
            showaddrs.append('%s: %s' % (header, addr))
            return mail.addrlistencode(ui, [addr], _charsets, opts.get('test'))
        elif default:
            return mail.addrlistencode(
                ui, [default], _charsets, opts.get('test'))
        return []

    to = getaddrs('To', ask=True)
    if not to:
        # we can get here in non-interactive mode
        raise error.Abort(_('no recipient addresses provided'))
    cc = getaddrs('Cc', ask=True, default='')
    bcc = getaddrs('Bcc')
    replyto = getaddrs('Reply-To')

    confirm = ui.configbool('patchbomb', 'confirm')
    confirm |= bool(opts.get('diffstat') or opts.get('confirm'))

    if confirm:
        ui.write(_('\nFinal summary:\n\n'), label='patchbomb.finalsummary')
        ui.write(('From: %s\n' % sender), label='patchbomb.from')
        for addr in showaddrs:
            ui.write('%s\n' % addr, label='patchbomb.to')
        for m, subj, ds in msgs:
            ui.write(('Subject: %s\n' % subj), label='patchbomb.subject')
            if ds:
                ui.write(ds, label='patchbomb.diffstats')
        ui.write('\n')
        if ui.promptchoice(_('are you sure you want to send (yn)?'
                             '$$ &Yes $$ &No')):
            raise error.Abort(_('patchbomb canceled'))

    ui.write('\n')

    parent = opts.get('in_reply_to') or None
    # angle brackets may be omitted, they're not semantically part of the msg-id
    if parent is not None:
        if not parent.startswith('<'):
            parent = '<' + parent
        if not parent.endswith('>'):
            parent += '>'

    sender_addr = eutil.parseaddr(encoding.strfromlocal(sender))[1]
    sender = mail.addressencode(ui, sender, _charsets, opts.get('test'))
    sendmail = None
    firstpatch = None
    progress = ui.makeprogress(_('sending'), unit=_('emails'), total=len(msgs))
    for i, (m, subj, ds) in enumerate(msgs):
        try:
            m['Message-Id'] = genmsgid(m['X-Mercurial-Node'])
            if not firstpatch:
                firstpatch = m['Message-Id']
            m['X-Mercurial-Series-Id'] = firstpatch
        except TypeError:
            m['Message-Id'] = genmsgid('patchbomb')
        if parent:
            m['In-Reply-To'] = parent
            m['References'] = parent
        if not parent or 'X-Mercurial-Node' not in m:
            parent = m['Message-Id']

        m['User-Agent'] = 'Mercurial-patchbomb/%s' % util.version()
        m['Date'] = eutil.formatdate(start_time[0], localtime=True)

        start_time = (start_time[0] + 1, start_time[1])
        m['From'] = sender
        m['To'] = ', '.join(to)
        if cc:
            m['Cc']  = ', '.join(cc)
        if bcc:
            m['Bcc'] = ', '.join(bcc)
        if replyto:
            m['Reply-To'] = ', '.join(replyto)
        # Fix up all headers to be native strings.
        # TODO(durin42): this should probably be cleaned up above in the future.
        if pycompat.ispy3:
            for hdr, val in list(m.items()):
                change = False
                if isinstance(hdr, bytes):
                    del m[hdr]
                    hdr = pycompat.strurl(hdr)
                    change = True
                if isinstance(val, bytes):
                    val = pycompat.strurl(val)
                    if not change:
                        # prevent duplicate headers
                        del m[hdr]
                    change = True
                if change:
                    m[hdr] = val
        if opts.get('test'):
            ui.status(_('displaying '), subj, ' ...\n')
            ui.pager('email')
            generator = _bytesgenerator(ui, mangle_from_=False)
            try:
                generator.flatten(m, 0)
                ui.write('\n')
            except IOError as inst:
                if inst.errno != errno.EPIPE:
                    raise
        else:
            if not sendmail:
                sendmail = mail.connect(ui, mbox=mbox)
            ui.status(_('sending '), subj, ' ...\n')
            progress.update(i, item=subj)
            if not mbox:
                # Exim does not remove the Bcc field
                del m['Bcc']
            fp = stringio()
            generator = _bytesgenerator(fp, mangle_from_=False)
            generator.flatten(m, 0)
            alldests = to + bcc + cc
            alldests = [encoding.strfromlocal(d) for d in alldests]
            sendmail(sender_addr, alldests, fp.getvalue())

    progress.complete()
