imports
exports (makeBuilder, expand)

def NODE_INFO :Map[Str, Int] := [
    "NounExpr"              => 1,
    "LiteralExpr"           => 1,
    "TempNounExpr"          => 1,
    "SlotExpr"              => 1,
    "MetaContextExpr"       => 0,
    "MetaStateExpr"         => 0,
    "BindingExpr"           => 1,
    "SeqExpr"               => 1,
    "Module"                => 3,
    "NamedArg"              => 2,
    "NamedArgExport"        => 1,
    "MethodCallExpr"        => 4,
    "FunCallExpr"           => 3,
    "SendExpr"              => 4,
    "FunSendExpr"           => 3,
    "GetExpr"               => 2,
    "AndExpr"               => 2,
    "OrExpr"                => 2,
    "BinaryExpr"            => 3,
    "CompareExpr"           => 3,
    "RangeExpr"             => 3,
    "SameExpr"              => 3,
    "MatchBindExpr"         => 2,
    "MismatchExpr"          => 2,
    "PrefixExpr"            => 2,
    "CoerceExpr"            => 2,
    "CurryExpr"             => 3,
    "ExitExpr"              => 2,
    "ForwardExpr"           => 1,
    "DefExpr"               => 3,
    "AssignExpr"            => 2,
    "VerbAssignExpr"        => 3,
    "AugAssignExpr"         => 3,
    "Method"                => 6,
    "To"                    => 6,
    "Matcher"               => 2,
    "Catcher"               => 2,
    "NamedParam"            => 3,
    "NamedParamImport"      => 2,
    "Script"                => 3,
    "FunctionScript"        => 4,
    "FunctionExpr"          => 2,
    "ListExpr"              => 1,
    "ListComprehensionExpr" => 5,
    "MapExprAssoc"          => 2,
    "MapExprExport"         => 1,
    "MapExpr"               => 1,
    "MapComprehensionExpr"  => 6,
    "ForExpr"               => 6,
    "ObjectExpr"            => 5,
    "ParamDesc"             => 2,
    "MessageDesc"           => 4,
    "InterfaceExpr"         => 6,
    "FunctionInterface"     => 6,
    "CatchExpr"             => 3,
    "FinallyExpr"           => 2,
    "TryExpr"               => 3,
    "EscapeExpr"            => 4,
    "SwitchExpr"            => 2,
    "WhenExpr"              => 4,
    "IfExpr"                => 3,
    "WhileExpr"             => 3,
    "HideExpr"              => 1,
    "ValueHoleExpr"         => 1,
    "PatternHoleExpr"       => 1,
    "ValueHolePattern"      => 1,
    "PatternHolePattern"    => 1,
    "FinalPattern"          => 2,
    "BindingPattern"        => 1,
    "SlotPattern"           => 2,
    "IgnorePattern"         => 1,
    "VarPattern"            => 2,
    "BindPattern"           => 2,
    "ListPattern"           => 2,
    "MapPatternAssoc"       => 3,
    "MapPatternImport"      => 2,
    "MapPattern"            => 2,
    "ViaPattern"            => 2,
    "SuchThatPattern"       => 2,
    "SamePattern"           => 2,
    "QuasiText"             => 1,
    "QuasiExprHole"         => 1,
    "QuasiPatternHole"      => 1,
    "QuasiParserExpr"       => 2,
    "QuasiParserPattern"    => 2,
]

def makeBuilder() as DeepFrozen:
    def tree := [].diverge()
    return object fastBuilder:
            to getTree():
                return tree
            match [v ? (NODE_INFO.contains(v)),
                   a :List ? (a.size() == (NODE_INFO[v] + 1)),
                   _]:
                def i := tree.size()
                tree.push(v)
                tree.extend(a)
                object astNodeish extends i:
                    # Just enough to fool the parser.
                    to getNodeName():
                        return v
                    to _conformTo(guard):
                        return i


def findTopNode(tree, ej) as DeepFrozen:
    # Fish around a bit for the last node added.
    def sizes := NODE_INFO.size().sort()
    for n in (sizes[0])..(sizes.last()):
        def i := tree.size() - i - 2
        if (NODE_INFO.fetch(tree[i], fn {null}) == n):
            return i
    ej("Could not find a start node, sorry")

def expand(builder, finalBuilder, fail) as DeepFrozen:
    def tree := builder.getTree()
    def stack := [findTopNode(tree, fail), "expand"].diverge()
    def outStack := [].diverge()
    while (stack.size() > 0):
        def op :Str := stack.pop()
        if (op == "out"):
            outStack.push(stack.pop())
        else if (op == "expandList"):
            def items := stack.pop()
            stack.push(items.size())
            stack.push("makeList")
            for item in items:
                stack.push(item)
                stack.push("expand")
        else if (op == "makeList"):
            def n := stack.pop()
            def l := outStack.slice(n)
            # XXX add a FlexList.delSlice method?
            for _ in 0..!n:
                outStack.pop()
            outStack.push(l)
        else if (op == "expand"):
            def node := stack.pop()
            def nodeName := tree[node]
            def siz := NODE_INFO[nodeName]
            def span := tree[node + 1 + siz]
            def getArg(n ? (n < siz)):
                return tree[node + 1 + n]
            def getArgs():
                return tree.slice(node + 1, node + 1 + siz)
            def nameFromNameExpr(n):
                def typ := tree[n]

            if (["BindingExpr", "NounExpr", "LiteralExpr"].contains(nodeName)):
                outStack.push(node)
            else if (nodeName == "SlotExpr"):
                stack.extend([span, "out",
                              [], "out",
                              [], "out",
                              "get", "out",
                              span, "out",
                              getArg(0), "out",
                              "BindingExpr",
                              "MethodCallExpr"])
            else if (nodeName == "MethodCallExpr"):
                def [rcvr, verb, arglist, namedArgs] := getArgs()
                stack.extend([span, "out",
                              namedArgs, "expandList",
                              arglist, "expandList",
                              verb, "out",
                              rcvr, "expand",
                              "MethodCallExpr"])
            else if (nodeName == "NamedArg"):
                def [k, v] := getArgs()
                stack.extend([span, "out",
                              v, "expand",
                              k, "expand",
                              "NamedArg"])
            else if (nodeName == "NamedArgExport"):
                def v := getArg(0)
                def vName := tree[v]
                def k := if (vName == "BindingExpr") {
                    "&&" + tree[v + 2]
                } else if (vName == "SlotExpr") {
                    "&" + tree[v + 2]
                } else {
                    tree[v + 1]
                }
                stack.extend([span, "out",
                              span, "out",
                              v, "expand",
                              k, "out",
                              "NounExpr",
                              "NamedArg"])
            else if (nodeName == "FunCallExpr"):
                def [receiver, fargs, namedArgs] := getArgs()
                stack.extend([span, "out",
                              namedArgs, "expandList",
                              fargs, "expandList",
                              "run", "out",
                              receiver, "expand",
                          "MethodCallExpr"])
        else if (NODE_INFO.maps(op)):
            tree.push(op)
            def n := NODE_INFO[op]
            for _ in 0..n:
                tree.push(outStack.pop())
            outStack.push(tree.size() - n)

    if (outStack.size() != 1):
        throw(`outstack shouldn't be $outStack`)
    def buildStack := [outStack.pop(), "build"].diverge()
    while (buildStack.size() > 0):
        def op := buildStack.pop()
        if (op == "build"):
            def node := buildStack.pop()
            def nodeName := tree[node]
            if (nodeName == "LiteralExpr"):
                outStack.push(finalBuilder.LiteralExpr(tree[node + 1], tree[node + 2]))
            else:
                def n := NODE_INFO[nodeName]
                for i in (0..n).descending():
                    def o := tree[node + i + 1]
                    if (o =~ _ :Int):
                        buildStack.push(o)
                        buildStack.push("build")
                    else if (o =~ _ :List):
                        buildStack.push(o)
                        buildStack.push("buildList")
                    else:
                        buildStack.push(o)
                        buildStack.push("out")
                buildStack.push(nodeName)
        else if (op == "buildList"):
            def items := buildStack.pop()
            buildStack.push(items.size())
            buildStack.push("makeList")
            for item in items:
                buildStack.push(item)
                buildStack.push("build")
        else if (op == "makeList"):
            def n := outStack.pop()
            def l := outStack.slice(n)
            # XXX add a FlexList.delSlice method?
            for _ in 0..!n:
                outStack.pop()
            outStack.push(l)
        else if (NODE_INFO.maps(op)):
            def arglist := [].diverge()
            for _ in 0..(NODE_INFO):
                arglist.push(outStack.pop())
            outStack.push(M.call(finalBuilder, op, arglist))

    return outStack[0]

