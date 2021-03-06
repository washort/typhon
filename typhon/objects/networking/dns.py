"""
DNS getaddrinfo().
"""

from rpython.rlib import _rsocket_rffi as s
from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.lltype import nullptr
from rpython.rtyper.lltypesystem.rffi import getintfield

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.collections.lists import ConstList
from typhon.objects.data import (bytesToString, unwrapBytes, BytesObject,
                                 StrObject)
from typhon.objects.refs import LocalResolver, makePromise
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat, scopedVat


GETADDRESS_0 = getAtom(u"getAddress", 0)
GETFAMILY_0 = getAtom(u"getFamily", 0)
GETSOCKETTYPE_0 = getAtom(u"getSocketType", 0)
RUN_2 = getAtom(u"run", 2)


socktypes = {
    s.SOCK_DGRAM: u"datagram",
    s.SOCK_RAW: u"raw",
    s.SOCK_RDM: u"reliable datagram",
    s.SOCK_SEQPACKET: u"packet",
    s.SOCK_STREAM: u"stream",
}


class AddrInfo(Object):

    _immutable_ = True

    def recv(self, atom, args):
        if atom is GETADDRESS_0:
            return BytesObject(self.addr)

        if atom is GETFAMILY_0:
            return StrObject(self.family)

        if atom is GETSOCKETTYPE_0:
            return StrObject(self.socktype)

        raise Refused(self, atom, args)


@autohelp
class IP4AddrInfo(AddrInfo):
    """
    Information about an IPv4 network address.
    """

    _immutable_ = True

    family = u"INET"

    def __init__(self, ai):
        self.flags = getintfield(ai, "c_ai_flags")
        self.socktype = socktypes.get(getintfield(ai, "c_ai_socktype"),
                                      u"unknown")
        # XXX getprotoent(3)
        self.protocol = getintfield(ai, "c_ai_protocol")
        self.addr = ruv.IP4Name(ai.c_ai_addr)

    def toString(self):
        return u"IP4AddrInfo(%s, %s, %d, %d)" % (bytesToString(self.addr),
                                                 self.socktype, self.protocol,
                                                 self.flags)


@autohelp
class IP6AddrInfo(AddrInfo):
    """
    Information about an IPv6 network address.
    """

    _immutable_ = True

    family = u"INET6"

    def __init__(self, ai):
        self.flags = getintfield(ai, "c_ai_flags")
        self.socktype = socktypes.get(getintfield(ai, "c_ai_socktype"),
                                      u"unknown")
        # XXX getprotoent(3)
        self.protocol = getintfield(ai, "c_ai_protocol")
        self.addr = ruv.IP6Name(ai.c_ai_addr)

    def toString(self):
        return u"IP6AddrInfo(%s, %s, %d, %d)" % (bytesToString(self.addr),
                                                 self.socktype, self.protocol,
                                                 self.flags)


def walkAI(ai):
    rv = []
    while ai:
        family = getintfield(ai, "c_ai_family")
        if family == s.AF_INET:
            rv.append(IP4AddrInfo(ai))
        elif family == s.AF_INET6:
            rv.append(IP6AddrInfo(ai))
        else:
            print "Skipping family", family, "for", ai
        ai = ai.c_ai_next
    return rv


def gaiCB(gai, status, ai):
    status = intmask(status)
    vat, resolver = ruv.unstashGAI(gai)
    with scopedVat(vat):
        assert isinstance(resolver, LocalResolver), "implementation error"
        if status < 0:
            msg = ruv.formatError(status).decode("utf-8")
            resolver.smash(StrObject(u"libuv error: %s" % msg))
        else:
            gaiList = walkAI(ai)
            resolver.resolve(ConstList(gaiList[:]))
    ruv.freeAddrInfo(ai)
    ruv.free(gai)


@runnable(RUN_2)
def getAddrInfo(node, service):
    node = unwrapBytes(node)
    service = unwrapBytes(service)
    vat = currentVat.get()
    gai = ruv.alloc_gai()
    p, r = makePromise()
    ruv.stashGAI(gai, (vat, r))
    ruv.getAddrInfo(vat.uv_loop, gai, gaiCB, node, service,
                    nullptr(ruv.s.addrinfo))
    return p
