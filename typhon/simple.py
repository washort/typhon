# Copyright (C) 2014 Google Inc. All rights reserved.
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

from typhon.errors import Refused, UserException
from typhon.objects.equality import Equalizer
from typhon.objects.collections import ConstList, ConstMap
from typhon.objects.constants import BoolObject, NullObject, wrapBool
from typhon.objects.data import CharObject, DoubleObject, IntObject, StrObject
from typhon.objects.ejectors import throw
from typhon.objects.guards import predGuard
from typhon.objects.iteration import accumulateList, loop
from typhon.objects.root import Object


@predGuard
def boolGuard(specimen):
    return isinstance(specimen, BoolObject)


@predGuard
def charGuard(specimen):
    return isinstance(specimen, CharObject)


@predGuard
def doubleGuard(specimen):
    return isinstance(specimen, DoubleObject)


@predGuard
def intGuard(specimen):
    return isinstance(specimen, IntObject)


@predGuard
def strGuard(specimen):
    return isinstance(specimen, StrObject)


@predGuard
def listGuard(specimen):
    return isinstance(specimen, ConstList)


@predGuard
def mapGuard(specimen):
    return isinstance(specimen, ConstMap)


class makeList(Object):

    def recv(self, verb, args):
        if verb == u"run":
            return ConstList(args)
        raise Refused(verb, args)


class Throw(Object):

    def repr(self):
        return "<throw>"

    def recv(self, verb, args):
        if verb == u"run" and len(args) == 1:
            raise UserException(args[0])
        if verb == u"eject" and len(args) == 2:
            return throw(args[0], args[1])
        raise Refused(verb, args)


def simpleScope():
    return {
        u"null": NullObject,

        u"false": wrapBool(False),
        u"true": wrapBool(True),

        u"Bool": boolGuard(),
        u"Char": charGuard(),
        u"Double": doubleGuard(),
        u"Int": intGuard(),
        u"List": listGuard(),
        u"Map": mapGuard(),
        u"Str": strGuard(),

        u"__accumulateList": accumulateList(),
        u"__equalizer": Equalizer(),
        u"__loop": loop(),
        u"__makeList": makeList(),
        u"throw": Throw(),
    }
