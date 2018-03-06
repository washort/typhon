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
from typhon.rpromise import Handler, Result
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
        self.fd = fd
        self.resolver = resolver

        self.pieces = []

        # XXX read size should be tunable
        self.buf = ruv.allocBuf(16384)

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
        return (bo, None, None)

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


def openGetContentsCB(fs):
    try:
        fd = intmask(fs.c_result)
        vat, r = ruv.unstashFS(fs)
        assert isinstance(r, LocalResolver)
        with scopedVat(vat):
            if fd < 0:
                msg = ruv.formatError(fd).decode("utf-8")
                r.smash(StrObject(u"Couldn't open file fount: %s" % msg))
            else:
                # Strategy: Read and use the callback to queue additional reads
                # until done. This call is known to its caller to be expensive, so
                # there's not much point in trying to be clever about things yet.
                gc = GetContents(vat, fd, r)
                gc.queueRead()
        ruv.fsDiscard(fs)
    except:
        print "Exception in openGetContentsCB"


def renameCB(fs):
    try:
        success = intmask(fs.c_result)
        vat, r = ruv.unstashFS(fs)
        if success < 0:
            msg = ruv.formatError(success).decode("utf-8")
            r.smash(StrObject(u"Couldn't rename file: %s" % msg))
        else:
            r.resolve(NullObject)
        ruv.fsDiscard(fs)
    except:
        print "Exception in renameCB"


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
        fs = ruv.alloc_fs()
        sb = ruv.scopedBufs([self.data], self)
        bufs = sb.allocate()
        ruv.stashFS(fs, (self.vat, sb))
        ruv.fsWrite(self.vat.uv_loop, fs, self.fd, bufs,
                    1, -1, writeSetContentsCB)

    def startWriting(self, fd):
        self.fd = fd
        self.queueWrite()

    def written(self, size):
        self.pos += size
        self.data = self.data[size:]
        if self.data:
            self.queueWrite()
        else:
            # Finished writing; let's move on to the rename.
            fs = ruv.alloc_fs()
            ruv.stashFS(fs, (self.vat, self))
            ruv.fsClose(self.vat.uv_loop, fs, self.fd,
                        closeSetContentsCB)

    def rename(self):
        # And issuing the rename is surprisingly straightforward.
        p = self.src.rename(self.dest.asBytes())
        self.resolver.resolve(p)


def openSetContentsCB(fs):
    try:
        fd = intmask(fs.c_result)
        vat, sc = ruv.unstashFS(fs)
        assert isinstance(sc, SetContents)
        if fd < 0:
            msg = ruv.formatError(fd).decode("utf-8")
            sc.fail(u"Couldn't open file fount: %s" % msg)
        else:
            sc.startWriting(fd)
        ruv.fsDiscard(fs)
    except:
        print "Exception in openSetContentsCB"


def writeSetContentsCB(fs):
    try:
        vat, sb = ruv.unstashFS(fs)
        sc = sb.obj
        assert isinstance(sc, SetContents)
        size = intmask(fs.c_result)
        if size >= 0:
            sc.written(size)
        else:
            msg = ruv.formatError(size).decode("utf-8")
            sc.fail(u"libuv error: %s" % msg)
        ruv.fsDiscard(fs)
        sb.deallocate()
    except:
        print "Exception in writeSetContentsCB"


def closeSetContentsCB(fs):
    try:
        vat, sc = ruv.unstashFS(fs)
        # Need to scope vat here.
        with scopedVat(vat):
            assert isinstance(sc, SetContents)
            size = intmask(fs.c_result)
            if size < 0:
                msg = ruv.formatError(size).decode("utf-8")
                sc.fail(u"libuv error: %s" % msg)
            else:
                # Success.
                sc.rename()
        ruv.fsDiscard(fs)
    except:
        print "Exception in closeSetContentsCB"


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
    def open(self, callback, flags=None, mode=None):
        # Always call this as .open(callback, flags=..., mode=...)
        assert flags is not None
        assert mode is not None

        p, r = makePromise()
        vat = currentVat.get()
        uv_loop = vat.uv_loop
        fs = ruv.alloc_fs()

        path = self.asBytes()
        log.log(["fs"], u"makeFileResource: Opening file '%s'" % path.decode("utf-8"))
        ruv.stashFS(fs, (vat, r))
        ruv.fsOpen(uv_loop, fs, path, flags, mode, callback)
        return p

    def rename(self, dest):
        p, r = makePromise()
        vat = currentVat.get()
        uv_loop = vat.uv_loop
        fs = ruv.alloc_fs()

        src = self.asBytes()
        ruv.stashFS(fs, (vat, r))
        ruv.fsRename(uv_loop, fs, src, dest, renameCB)
        return p

    def sibling(self, segment):
        return FileResource(self.segments[:-1] + [segment])

    def temporarySibling(self, suffix):
        fileName = rsodium.randomHex() + suffix
        return self.sibling(fileName)

    @method("Any")
    def getContents(self):
        return self.open(openGetContentsCB, flags=os.O_RDONLY, mode=0000)

    @method("Any", "Bytes")
    def setContents(self, data):
        sibling = self.temporarySibling(".setContents")

        p, r = makePromise()
        vat = currentVat.get()
        uv_loop = vat.uv_loop
        fs = ruv.alloc_fs()

        path = sibling.asBytes()
        # Use CREAT | EXCL to cause a failure if the temporary file
        # already exists.
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        sc = SetContents(vat, data, r, sibling, self)
        ruv.stashFS(fs, (vat, sc))
        ruv.fsOpen(uv_loop, fs, path, flags, 0777, openSetContentsCB)
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
