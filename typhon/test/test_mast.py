from twisted.trial.unittest import FailTest, TestCase

from typhon.nanopass import CompilerFailed
from typhon.nano.mast import MastIR, SanityCheck, SaveScriptIR as ssi
from typhon.nano.slots import NoAssignIR as nai, RemoveAssign

def assertAstSame(left, right):
    if left == right:
        return
    if isinstance(left, list):
        if not isinstance(right, list):
            raise FailTest("%r != %r" % (left, right))
        for l, r in zip(left, right):
            assertAstSame(l, r)
        return

    if type(left) != type(right):
        raise FailTest("%r instance expected, %s found" %
                        (type(left), type(right)))
    if left._immutable_fields_ and right._immutable_fields_:
        leftR, rightR = left.__reduce__()[2], right.__reduce__()[2]
        for k, v in leftR.iteritems():
            assertAstSame(v, rightR[k])


class SanityCheckTests(TestCase):
    def test_viaPattObjects(self):
        oAst = MastIR.ObjectExpr(
            None,
            MastIR.ViaPatt(MastIR.CallExpr(
                MastIR.NounExpr(u"foo"),
                u"run",
                [MastIR.NounExpr(u"x")], []),
                           MastIR.FinalPatt(u"x", None), None),
            [], [], [])

        self.assertRaises(CompilerFailed, SanityCheck().visitExpr, oAst)


class RemoveAssignTests(TestCase):
    def test_rewriteAssign(self):
        ast1 = ssi.SeqExpr([
            ssi.AssignExpr(u"blee", ssi.IntExpr(1)),
            ssi.NounExpr(u"blee")
            ])
        ast2 = nai.SeqExpr([
            nai.HideExpr(nai.SeqExpr([
                nai.DefExpr(nai.TempPatt(u"_tempAssign"), nai.NullExpr(), nai.IntExpr(1)),
                nai.CallExpr(nai.SlotExpr(u"blee"), u"put",
                             [nai.TempNounExpr(u"_tempAssign")], []),
                nai.TempNounExpr(u"_tempAssign")])),
            nai.NounExpr(u"blee")
            ])

        assertAstSame(ast2, RemoveAssign().visitExpr(ast1))
