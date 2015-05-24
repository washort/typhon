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

from typhon.atoms import getAtom
from typhon.errors import Refused, userError
from typhon.objects.constants import NullObject
from typhon.objects.root import Object


GET_0 = getAtom(u"get", 0)
GETGUARD_0 = getAtom(u"getGuard", 0)
PUT_1 = getAtom(u"put", 1)


class Binding(Object):
    """
    A slot and a guard describing the nature of the slot.
    """

    _immutable_ = True

    def __init__(self, slot):
        self.slot = slot
        self.guard = NullObject

    def toString(self):
        return u"<binding for %s>" % self.slot.toString()

    def recv(self, atom, args):
        if atom is GET_0:
            return self.slot

        if atom is GETGUARD_0:
            return NullObject

        raise Refused(self, atom, args)


class Slot(Object):
    """
    A storage space.
    """

    def recv(self, atom, args):
        if atom is GET_0:
            return self.get()

        if atom is PUT_1:
            return self.put(args[0])

        raise Refused(self, atom, args)


class FinalSlot(Slot):

    _immutable_ = True

    def __init__(self, obj):
        self._obj = obj

    def toString(self):
        return u"<FinalSlot(%s)>" % self._obj.toString()

    def get(self):
        return self._obj

    def put(self, value):
        raise userError(u"Can't put into a FinalSlot!")


class VarSlot(Slot):

    def __init__(self, obj, guard, ej):
        self._guard = guard
        self._ej = ej

        # The initial coercion has not yet been done; we are responsible for
        # performing it here. Cheat and reuse the put() method.
        self.put(obj)

    def toString(self):
        return u"<VarSlot(%s, %s)>" % (self._obj.toString(),
                                       self._guard.toString())

    def get(self):
        return self._obj

    def put(self, value):
        if self._guard is NullObject:
            self._obj = value
        else:
            self._obj = self._guard.call(u"coerce", [value, self._ej])
        return NullObject
