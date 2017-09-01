exports (normalize)


def normalize(ast, builder) as DeepFrozen:
    def normalizeTransformer(node, maker, args, span):
        return switch (node.getNodeName()):
            match =="LiteralExpr":
                switch (args[0]):
                    match i :Int:
                        builder.IntExpr(i, span)
                    match s :Str:
                        builder.StrExpr(s, span)
                    match c :Char:
                        builder.CharExpr(c, span)
                    match d :Double:
                        builder.DoubleExpr(d, span)
            match =="MethodCallExpr":
                def [obj, verb, args, namedArgs] := args
                builder.CallExpr(obj, verb, args, namedArgs, span)
            match =="EscapeExpr":
                if (args =~ [patt, body, ==null, ==null]):
                    builder.EscapeOnlyExpr(patt, body, span)
                else:
                    def [ejPatt, ejBody, catchPatt, catchBody] := args
                    builder.EscapeExpr(ejPatt, ejBody, catchPatt, catchBody, span)
            match =="ObjectExpr":
                def [doc, name, asExpr, auditors, [methods, matchers], span] := args
                builder.ObjectExpr(doc, name, [asExpr] + auditors, methods, matchers,
                                   span)
            match =="IgnorePattern":
                def [guard] := args
                builder.IgnorePatt(guard, span)
            match =="BindingPatt":
                def [name] := args
                builder.BindingPatt(name, span)
            match =="FinalPatt":
                def [name, guard] := args
                builder.FinalPatt(name, guard, span)
            match =="VarPatt":
                def [name, guard] := args
                builder.VarPatt(name, guard, span)
            match =="ListPatt":
                def [patts, _] := args
                builder.ListPatt(patts, span)
            match =="ViaPatt":
                def [expr, patt] := args
                builder.ViaPatt(expr, patt, span)
            match =="NamedArg":
                def [key, value] := args
                builder.NamedArgExpr(key, value, span)
            match =="NamedParam":
                def [k, p, d] := args
                builder.NamedPattern(k, p, d, span)
            match =="Matcher":
                def [patt, body] := args
                builder.MatcherExpr(patt, body, span)
            match =="Method":
                def [doc, verb, patts, namedPatts, guard, body] := args
                builder.MethodExpr(doc, verb, patts, namedPatts, guard, body, span)
            match nodeName:
                M.call(builder, nodeName, args + [span])

    return ast.transform(normalizeTransformer)
