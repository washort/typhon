import "boot" =~ [=> DeepFrozenStamp]
exports (printerActions)

def all(iterable, pred) as DeepFrozenStamp:
    for item in (iterable):
        if (!pred(item)):
            return false
    return true

def MONTE_KEYWORDS :List[Str] := [
"as", "bind", "break", "catch", "continue", "def", "else", "escape",
"exit", "extends", "exports", "finally", "fn", "for", "guards", "if",
"implements", "in", "interface", "match", "meta", "method", "module",
"object", "pass", "pragma", "return", "switch", "to", "try", "var",
"via", "when", "while", "_"]

def idStart :List[Char] := _makeList.fromIterable("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
def idPart :List[Char] := idStart + _makeList.fromIterable("0123456789")
def INDENT :Str := "    "

# note to future drunk self: lower precedence number means add parens when
# inside a higher-precedence-number expression
def priorities :Map[Str, Int] := [
     "indentExpr" => 0,
     "braceExpr" => 1,
     "assign" => 2,
     "logicalOr" => 3,
     "logicalAnd" => 4,
     "comp" => 5,
     "order" => 6,
     "interval" => 7,
     "shift" => 8,
     "addsub" => 9,
     "divmul" => 10,
     "pow" => 11,
     "prefix" => 12,
     "send" => 13,
     "coerce" => 14,
     "call" => 15,
     "prim" => 16,

     "pattern" => 0]

def isIdentifier(name :Str) :Bool as DeepFrozenStamp:
    if (MONTE_KEYWORDS.contains(name.toLowerCase())):
        return false
    return idStart.contains(name[0]) && all(name.slice(1), idPart.contains)

def printListOn(left, nodes, sep, right, out, priority) as DeepFrozenStamp:
    out.print(left)
    if (nodes.size() >= 1):
        for n in (nodes.slice(0, nodes.size() - 1)):
            n.subPrintOn(out, priority)
            out.print(sep)
        nodes.last().subPrintOn(out, priority)
    out.print(right)

def printDocstringOn(docstring, out, indentLastLine) as DeepFrozenStamp:
    if (docstring == null):
        if (indentLastLine):
            out.println("")
        return
    out.lnPrint("\"")
    def lines := docstring.split("\n")
    for line in (lines.slice(0, 0.max(lines.size() - 2))):
        out.println(line)
    if (lines.size() > 0):
        out.print(lines.last())
    if (indentLastLine):
        out.println("\"")
    else:
        out.print("\"")

def printSuiteOn(leaderFn, printContents, cuddle, noLeaderNewline, out,
                 priority) as DeepFrozenStamp:
    def indentOut := out.indent(INDENT)
    if (priorities["braceExpr"] <= priority):
        if (cuddle):
            out.print(" ")
        leaderFn()
        if (noLeaderNewline):
            indentOut.print(" {")
        else:
            indentOut.println(" {")
        printContents(indentOut, priorities["braceExpr"])
        out.println("")
        out.print("}")
    else:
        if (cuddle):
            out.println("")
        leaderFn()
        if (noLeaderNewline):
            indentOut.print(":")
        else:
            indentOut.println(":")
        printContents(indentOut, priorities["indentExpr"])

def printExprSuiteOn(leaderFn, suite, cuddle, out, priority) as DeepFrozenStamp:
        printSuiteOn(leaderFn, suite.subPrintOn, cuddle, false, out, priority)

def printDocExprSuiteOn(leaderFn, docstring, suite, out, priority) as DeepFrozenStamp:
        printSuiteOn(leaderFn, fn o, p {
            printDocstringOn(docstring, o, true)
            suite.subPrintOn(o, p)
            }, false, true, out, priority)

def printObjectSuiteOn(leaderFn, docstring, suite, out, priority) as DeepFrozenStamp:
        printSuiteOn(leaderFn, fn o, p {
            printDocstringOn(docstring, o, false)
            suite.subPrintOn(o, p)
            }, false, true, out, priority)

def printerActions :Map[Str, DeepFrozen] := [
    "LiteralExpr" => def printLiteralExpr(self, out, priority) as DeepFrozenStamp {
        out.quote(self.getValue())
    },
    "NounExpr" => def printNounExpr(self, out, priority) as DeepFrozenStamp {
        def name := self.getName()
        if (isIdentifier(name)) {
        out.print(name)
        } else {
            out.print("::")
            out.quote(name)
        }
    },
    "SlotExpr" => def printSlotExpr(self, out, priority) as DeepFrozenStamp {
        out.print("&")
        out.print(self.getNoun())
    },
    "SeqExpr" => def printSeqExpr(self, out, priority) as DeepFrozenStamp {
        if (priority > priorities["braceExpr"]) {
            out.print("(")
        }
        var first := true
        if (priorities["braceExpr"] >= priority && self.getExprs() == []) {
            out.print("pass")
        }
        for e in (self.getExprs()) {
            if (!first) {
                out.println("")
            }
            first := false
            e.subPrintOn(out, priority.min(priorities["braceExpr"]))
        }
        if (priority > priorities["braceExpr"]) {
            out.print(")")
        }
    },
    "Module" => def printModule(self, out, priority) as DeepFrozenStamp {
        for [petname, patt] in (self.getImports()) {
            out.print("import ")
            out.quote(petname)
            out.print(" =~ ")
            out.println(patt)
        }
        def exportsList := self.getExports()
        if (exportsList.size() > 0) {
            out.print("exports ")
            printListOn("(", exportsList, ", ", ")", out, priorities["braceExpr"])
            out.println("")
        }
        self.getBody().subPrintOn(out, priorities["indentExpr"])
    },
    "NamedArg" => def printNamedArg(self, out, priority) as DeepFrozenStamp {
        self.getKey().subPrintOn(out, priorities["prim"])
        out.print(" => ")
        self.getValue().subPrintOn(out, priorities["braceExpr"])
    },
    "NamedArgExport" => def printNamedArgExport(self, out, priority) as DeepFrozenStamp {
        out.print(" => ")
        self.getValue().subPrintOn(out, "braceExpr")
    },
    "MethodCallExpr" => def printMethodCallExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        out.print(".")
        def verb := self.getVerb()
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        printListOn("(", self.getArgs() + self.getNamedArgs(), ", ",
                    ")", out, priorities["braceExpr"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "FunCallExpr" => def printFunCallExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        printListOn("(", self.getArgs() + self.getNamedArgs(),
                    ", ", ")", out, priorities["braceExpr"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "SendExpr" => def printSendExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        out.print(" <- ")
        def verb := self.getVerb()
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        printListOn("(", self.getArgs() + self.getNamedArgs(),
                    ", ", ")", out, priorities["braceExpr"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "FunSendExpr" => def printFunSendExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        printListOn(" <- (", self.getArgs() + self.getNamedArgs(),
                    ", ", ")", out, priorities["braceExpr"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "GetExpr" => def printGetExpr(self, out, priority) as DeepFrozenStamp {
        self.getReceiver().subPrintOn(out, priorities["call"])
        printListOn("[", self.getIndices(), ", ", "]", out, priorities["braceExpr"])
        },
    "AndExpr" => def printAndExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["logicalAnd"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["logicalAnd"])
        out.print(" && ")
        self.getRight().subPrintOn(out, priorities["logicalAnd"])
        if (priorities["logicalAnd"] < priority) {
            out.print(")")
        }
    },
    "OrExpr" => def printOrExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["logicalOr"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["logicalOr"])
        out.print(" || ")
        self.getRight().subPrintOn(out, priorities["logicalOr"])
        if (priorities["logicalOr"] < priority) {
            out.print(")")
        }
    },
    "BinaryExpr" => def printBinaryExpr(self, out, priority) as DeepFrozenStamp {
        def opPrio := priorities[self.getPriorityName()]
        if (opPrio < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, opPrio)
        out.print(" ")
        out.print(self.getOp())
        out.print(" ")
        self.getRight().subPrintOn(out, opPrio)
        if (opPrio < priority) {
            out.print(")")
        }
    },
    "CompareExpr" => def printCompareExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["comp"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["comp"])
        out.print(" ")
        out.print(self.getOp())
        out.print(" ")
        self.getRight().subPrintOn(out, priorities["comp"])
        if (priorities["comp"] < priority) {
            out.print(")")
        }
    },
    "RangeExpr" => def printRangeExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["interval"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["interval"])
        out.print(self.getOp())
        self.getRight().subPrintOn(out, priorities["interval"])
        if (priorities["interval"] < priority) {
            out.print(")")
        }
    },
    "SameExpr" => def printSameExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["comp"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["comp"])
        if (self.getDirection()) {
            out.print(" == ")
        } else {
            out.print(" != ")
        }
        self.getRight().subPrintOn(out, priorities["comp"])
        if (priorities["comp"] < priority) {
            out.print(")")
        }
    },
    "MatchBindExpr" => def printMatchBindExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getSpecimen().subPrintOn(out, priorities["call"])
        out.print(" =~ ")
        self.getPattern().subPrintOn(out, priorities["pattern"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "MismatchExpr" => def printMismatchExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getSpecimen().subPrintOn(out, priorities["call"])
        out.print(" !~ ")
        self.getPattern().subPrintOn(out, priorities["pattern"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "PrefixExpr" => def printPrefixExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        out.print(self.getOp())
        self.getReceiver().subPrintOn(out, priorities["call"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "CoerceExpr" => def printCoerceExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["coerce"] < priority) {
            out.print("(")
        }
        self.getSpecimen().subPrintOn(out, priorities["coerce"])
        out.print(" :")
        self.getGuard().subPrintOn(out, priorities["prim"])
        if (priorities["coerce"] < priority) {
            out.print(")")
        }
    },
    "CurryExpr" => def printCurryExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        if (self.getIsSend()) {
            out.print(" <- ")
        } else {
            out.print(".")
        }
        def verb := self.getVerb()
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        if (priorities["call"] < priority) {
            out.print(")")
        }
   },
    "ExitExpr" => def printExitExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        out.print(self.getName())
        if (self.getValue() != null) {
            out.print(" ")
            self.getValue().subPrintOn(out, priority)
        }
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "ForwardExpr" => def printForwardExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        out.print("def ")
        self.getNoun().subPrintOn(out, priorities["prim"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "DefExpr" => def printDefExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        def pattern := self.getPattern()
        if (!["VarPattern", "BindPattern"].contains(pattern.getNodeName())) {
            out.print("def ")
        }
        pattern.subPrintOn(out, priorities["pattern"])
        def exit_ := self.getExit()
        if (exit_ != null) {
            out.print(" exit ")
            exit_.subPrintOn(out, priorities["call"])
        }
        out.print(" := ")
        self.getExpr().subPrintOn(out, priorities["assign"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "AssignExpr" => def printAssignExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        self.getLvalue().subPrintOn(out, priorities["call"])
        out.print(" := ")
        self.getRvalue().subPrintOn(out, priorities["assign"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "VerbAssignExpr" => def printVerbAssignExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        self.getLvalue().subPrintOn(out, priorities["call"])
        out.print(" ")
        def verb := self.getVerb()
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        out.print("= ")
        printListOn("(", self.getRvalues(), ", ", ")", out,
                    priorities["assign"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "AugAssignExpr" => def printAugAssignExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        self.getLvalue().subPrintOn(out, priorities["call"])
        out.print(" ")
        out.print(self.getOp())
        out.print("= ")
        self.getRvalue().subPrintOn(out, priorities["assign"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    # "Method" => def printMethod(self, out, priority) as DeepFrozenStamp {
    # },
    # "Matcher" => def printMatcher(self, out, priority) as DeepFrozenStamp {
    # },
    # "Catcher" => def printCatcher(self, out, priority) as DeepFrozenStamp {
    # },
    # "Script" => def printScript(self, out, priority) as DeepFrozenStamp {
    # },
    # "FunctionScript" => def printFunctionScript(self, out, priority) as DeepFrozenStamp {
    # },
    # "FunctionExpr" => def printFunctionExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "ListExpr" => def printListExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "MapExprAssoc" => def printMapExprAssoc(self, out, priority) as DeepFrozenStamp {
    # },
    # "MapExprExport" => def printMapExprExport(self, out, priority) as DeepFrozenStamp {
    # },
    # "MapExpr" => def printMapExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "MapComprehensionExpr" => def printMapComprehensionExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "ForExpr" => def printForExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "ObjectExpr" => def printObjectExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "ParamDesc" => def printParamDesc(self, out, priority) as DeepFrozenStamp {
    # },
    # "MessageDesc" => def printMessageDesc(self, out, priority) as DeepFrozenStamp {
    # },
    # "InterfaceExpr" => def printInterfaceExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "FunctionInterfaceExpr" => def printFunctionInterfaceExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "CatchExpr" => def printCatchExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "TryExpr" => def printTryExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "EscapeExpr" => def printEscapeExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "SwitchExpr" => def printSwitchExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "WhenExpr" => def printWhenExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "IfExpr" => def printIfExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "WhileExpr" => def printWhileExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "HideExpr" => def printHideExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "ValueHoleExpr" => def printValueHoleExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "PatternHoleExpr" => def printPatternHoleExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "ValueHolePattern" => def printValueHolePattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "PatternHolePattern" => def printPatternHolePattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "FinalP_attern" => def printFinalPattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "SlotPattern" => def printSlotPattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "BindingPattern" => def printBindingPattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "VarPattern" => def printVarPattern(self, out, priority) as DeepFrozenStamp {
    #     out.print("var ")
    #     self.getNoun().subPrintOn(out, priority)
    #     def guard := self.getGuard()
    #     if (guard != null) {
    #         out.print(" :")
    #         guard.subPrintOn(out, priorities["order"])
    #     }
    # },
    # "BindPattern" => def printBindPattern(self, out, priority) as DeepFrozenStamp {
    #     out.print("bind ")
    #     self.getNoun().subPrintOn(out, priority)
    #     def guard := self.getGuard()
    #     if (guard != null) {
    #         out.print(" :")
    #         guard.subPrintOn(out, priorities["order"])
    #     }
    # },
    # "ListPattern" => def printListPattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "MapPatternAssoc" => def printMapPatternAssoc(self, out, priority) as DeepFrozenStamp {
    # },
    # "MapPatternImport" => def printMapPatternImport(self, out, priority) as DeepFrozenStamp {
    # },
    # "MapPattern" => def printMapPattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "NamedParam" => def printNamedParam(self, out, priority) as DeepFrozenStamp {
    # },
    # "NamedParamImport" => def printNamedParamImport(self, out, priority) as DeepFrozenStamp {
    # },
    # "ViaPattern" => def printViaPattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "SuchThatPattern" => def printSuchThatPattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "SamePattern" => def printSamePattern(self, out, priority) as DeepFrozenStamp {
    # },
    # "QuasiText" => def printQuasiText(self, out, priority) as DeepFrozenStamp {
    # },
    # "QuasiExprHole" => def printQuasiExprHole(self, out, priority) as DeepFrozenStamp {
    # },
    # "QuasiPatternHole" => def printQuasiPatternHole(self, out, priority) as DeepFrozenStamp {
    # },
    # "QuasiParserExpr" => def printQuasiParserExpr(self, out, priority) as DeepFrozenStamp {
    # },
    # "QuasiParserPattern" => def printQuasiParserPattern(self, out, priority) as DeepFrozenStamp {
    # },
]
