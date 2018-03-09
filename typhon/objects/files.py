# Copyright (C) 2015 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import os

from rpython.rlib.objectmodel import specialize
from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.lltype import scoped_alloc
from rpython.rtyper.lltypesystem.rffi import charpsize2str

# from typhon.macros import macros, when, catch

from typhon import log, rsodium, ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, StrObject, unwrapStr
from typhon.objects.refs import LocalResolver, makePromise
from typhon.objects.root import Object, runnable
from typhon.rpromise import Handler
from typhon.vats import currentVat, scopedVat


ABORTFLOW_0 = getAtom(u"abortFlow", 0)
FLOWABORTED_1 = getAtom(u"flowAborted", 1)
FLOWSTOPPED_1 = getAtom(u"flowStopped", 1)
RECEIVE_1 = getAtom(u"receive", 1)
RUN_1 = getAtom(u"run", 1)


@autohelp
class FileUnpauser(Object):
    """
    A pause on a file fount.
    """

    def __init__(self, fount):
        self.fount = fount

    @method("Void")
    def unpause(self):
        if self.fount is not None:
            self.fount.unpause()
            # Let go so that the fount can be GC'd if necessary.
            self.fount = None


class GetContents(Object):
    """
    Struct used to manage getContents/0 calls.

    Has to be an Object so that it can be unified with LocalResolver.
    No, seriously.
    """

    # Our position reading from the file.
    pos = 0

    def __init__(self, vat, fd, resolver):
        self.vat = vat
        self.resolver = resolver

        self.pieces = []

        # XXX read size should be tunable
        self.buf = ruv.allocBuf(16384)
        self.fd = fd

    def append(self, data):
        self.pieces.append(data)
        self.pos += len(data)
        # Queue another!
        return self.queueRead()

    def succeed(self):
        # Clean up libuv stuff.
        fs = ruv.alloc_fs()
        ruv.stashFS(fs, (self.vat, self))
        ruv.fsClose(self.vat.uv_loop, fs, self.fd, ruv.fsUnstashAndDiscard)

        # Finally, resolve.
        buf = "".join(self.pieces)
        bo = BytesObject(buf)
        self.resolver.resolve(bo)
        return (None, None, None)

    def fail(self, reason):
        # Clean up libuv stuff.
        fs = ruv.alloc_fs()
        ruv.stashFS(fs, (self.vat, self))
        ruv.fsClose(self.vat.uv_loop, fs, self.fd, ruv.fsUnstashAndDiscard)

        # And resolve.
        self.resolver.smash(StrObject(u"libuv error: %s" % reason))
        return (None, None, None)

    def queueRead(self):
        p = ruv.magic_fsRead(self.vat, self.fd).then(FsReadHandler(self))
        return (None, None, p)


class FsReadHandler(Handler):
    def __init__(self, reader):
        Handler.__init__(self)
        self.reader = reader

    def onFulfilled(self, result):
        data = result[0]
        if data != "":
            return self.reader.append(data)
        else:
            return self.reader.succeed()

    def onRejected(self, result):
        return self.reader.fail(result[1])


class SetContents(Object):

    pos = 0

    def __init__(self, vat, data, resolver, src, dest):
        self.vat = vat
        self.data = data
        self.resolver = resolver
        self.src = src
        self.dest = dest

    def fail(self, reason):
        self.resolver.smash(StrObject(reason))

    def queueWrite(self):
        return ruv.magic_fsWrite(self.vat, self.fd, self.data).then(
            SetContentsHandler(self))

    def startWriting(self, fd):
        assert isinstance(fd, int)
        self.fd = fd
        return self.queueWrite()

    def written(self, size):
        self.pos += size
        self.data = self.data[size:]
        if self.data:
            return self.queueWrite()
        else:
            return ruv.magic_fsClose(self.vat, self.fd).then(
                CloseSetContentsHandler(self))

    def rename(self):
        # And issuing the rename is surprisingly straightforward.
        p = self.src.rename(self.dest.asBytes())
        self.resolver.resolve(p)


class SetContentsHandler(Handler):
    def __init__(self, sc):
        self.sc = sc

    def onFulfilled(self, result):
        # if result[0] is None:
        #    return result
        return self.sc.written(result[0])

    def onRejected(self, err):
        if err[1] is None:
            return err
        self.sc.fail(u"libuv error: " + err[1])


class CloseSetContentsHandler(Handler):
    def __init__(self, sc):
        self.sc = sc

    def onFulfilled(self, result):
        # if result[0] is None:
        #     return result
        return self.sc.rename()

    def onRejected(self, err):
        # if err[1] is None:
        #     return err
        self.sc.fail(u"libuv error: " + err[1])


class OpenGetContents(Handler):
    """Documentation for OpenGetContents

    """
    def __init__(self, vat, monteResolver):
        Handler.__init__(self)
        self.vat = vat
        self.monteResolver = monteResolver

    def onFulfilled(self, result):
        # if result[0] is None:
        #     return result
        fd = result[0]
        assert isinstance(fd, int)
        gc = GetContents(self.vat, fd, self.monteResolver)
        return gc.queueRead()

    def onRejected(self, err):
        return err


class OpenSetContents(Handler):
    def __init__(self, vat, data, r, sibling, fileObj):
        Handler.__init__(self)
        self.vat = vat
        self.data = data
        self.r = r
        self.sibling = sibling
        self.fileObj = fileObj

    def onFulfilled(self, result):
        # if result[0] is None:
        #     return result
        return SetContents(self.vat, self.data, self.r, self.sibling,
                           self.fileObj).startWriting(result[0])

    def onRejected(self, err):
        # if err[1] is None:
        #     return err
        return (None, u"Couldn't open file fount: " + err[1], None)


class RenameHandler(Handler):
    def __init__(self, monteResolver):
        Handler.__init__(self)
        self.monteResolver = monteResolver
    def onFulfilled(self, result):
        self.monteResolver.resolve(NullObject)
        return (None, None, None)
    def onRejected(self, err):
        self.monteResolver.smash(StrObject(u"Couldn't rename file: %s" % err[1]))
        return (None, None, None)


@autohelp
class FileResource(Object):
    """
    A Resource which provides access to the file system of the current
    process.
    """

    # For help understanding this class, consult FilePath, the POSIX
    # standards, and a bottle of your finest and strongest liquor. Perhaps not
    # in that order, though.

    _immutable_fields_ = "segments[*]",

    def __init__(self, segments):
        self.segments = segments

    def toString(self):
        return u"<file resource %s>" % self.asBytes().decode("utf-8")

    def asBytes(self):
        return "/".join(self.segments)

    @specialize.call_location()
    def open(self, flags=None, mode=None):
        assert flags is not None
        assert mode is not None

        vat = currentVat.get()
        path = self.asBytes()
        log.log(["fs"], u"makeFileResource: Opening file '%s'" % path.decode("utf-8"))
        return ruv.magic_fsOpen(vat, path, flags, mode)

    def rename(self, dest):
        p, r = makePromise()
        vat = currentVat.get()
        uv_loop = vat.uv_loop
        fs = ruv.alloc_fs()

        src = self.asBytes()
        ruv.magic_fsRename(vat, src, dest).then(RenameHandler(r))
        return p

    def sibling(self, segment):
        return FileResource(self.segments[:-1] + [segment])

    def temporarySibling(self, suffix):
        fileName = rsodium.randomHex() + suffix
        return self.sibling(fileName)

    @method("Any")
    def getContents(self):
        p, r = makePromise()
        vat = currentVat.get()
        self.open(flags=os.O_RDONLY, mode=0000).then(
            OpenGetContents(vat, r))
        return p

    @method("Any", "Bytes")
    def setContents(self, data):
        sibling = self.temporarySibling(".setContents")

        p, r = makePromise()
        vat = currentVat.get()
        path = sibling.asBytes()
        # Use CREAT | EXCL to cause a failure if the temporary file
        # already exists.
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        ruv.magic_fsOpen(vat, path, flags, 0777).then(
            OpenSetContents(vat, data, r, sibling, self))
        return p

    @method("Any", "Any", _verb="rename")
    def _rename(self, fr):
        if not isinstance(fr, FileResource):
            raise userError(u"rename/1: Must be file resource")
        return self.rename(fr.asBytes())

    @method("Any", "Str", _verb="sibling")
    def _sibling(self, name):
        if u'/' in name:
            raise userError(u"sibling/1: Illegal file name '%s'" % name)
        return self.sibling(name.encode("utf-8"))

    @method("Any", _verb="temporarySibling")
    def _temporarySibling(self):
        return self.temporarySibling(".new")


@runnable(RUN_1)
def makeFileResource(path):
    """
    Make a file Resource.
    """

    path = unwrapStr(path)
    segments = [segment.encode("utf-8") for segment in path.split(u'/')]
    if not path.startswith(u'/'):
        # Relative path.
        segments = os.getcwd().split('/') + segments
        log.log(["fs"], u"makeFileResource.run/1: Relative path '%s'" % path)
    return FileResource(segments)
