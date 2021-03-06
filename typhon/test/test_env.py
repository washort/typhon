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

from unittest import TestCase

from typhon.env import Environment
from typhon.errors import UserException
from typhon.objects.constants import NullObject
from typhon.objects.slots import Binding, FinalSlot
from typhon.scopes.safe import theFinalSlotGuardMaker


class TestEnv(TestCase):

    def testFinalImmutabilityFrame(self):
        env = Environment([Binding(FinalSlot(NullObject, NullObject),
                                   theFinalSlotGuardMaker)],
                          [], 0, 0, 0)
        self.assertRaises(UserException, env.putValueFrame, 0, NullObject)

    def testFinalImmutabilityLocal(self):
        env = Environment([], [], 1, 0, 0)
        env.createSlotLocal(0, FinalSlot(NullObject, NullObject),
                            theFinalSlotGuardMaker)
        self.assertRaises(UserException, env.putValueLocal, 0, NullObject)
