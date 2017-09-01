import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
exports (makeMASTContext, readMAST)

def packInt(var i :(Int >= 0)) :Bytes as DeepFrozen:
    if (i == 0):
        return b`$\x00`

    def l := [].diverge()
    while (i > 0):
        def chunk := i & 0x7f
        i >>= 7
        l.push(if (i > 0) {chunk | 0x80} else {chunk})
    return _makeBytes.fromInts(l)

def packRefs(bss :List[Bytes]) :Bytes as DeepFrozen:
    def size := packInt(bss.size())
    return size + b``.join(bss)

def packStr(s :NullOk[Str]) :Bytes as DeepFrozen:
    if (s == null) {return b`$\x00`}
    def bs := UTF8.encode(s, null)
    return packInt(bs.size()) + bs

def nullSpanBytes :Bytes := b`B$\x00$\x00$\x00$\x00`

def packSpan(s) :Bytes as DeepFrozen:
    if (s == null) { return nullSpanBytes }
    def type := if (s.isOneToOne()) { b`S` } else { b`B` }
    def startLine := packInt(s.getStartLine())
    def startCol := packInt(s.getStartCol())
    def endLine := packInt(s.getEndLine())
    def endCol := packInt(s.getEndCol())
    return type + startLine + startCol + endLine + endCol

def MAGIC :Bytes := b`Mont$\xe0MAST$\x01`

def makeMASTContext() as DeepFrozen:
    "Make a MAST context."

    var exprIndex :Int := 0
    var pattIndex :Int := 0
    def streams := [MAGIC].diverge()

    return object MASTContext:
        "A MAST context."

        to run(expr) :Void:
            "Add an expression to this context."
            MASTContext.appendExpr(expr)

        to bytes() :Bytes:
            return b``.join(streams)

        to appendExpr(expr) :Int:
            def bs :Bytes := MASTContext.addExpr(expr)
            def span := if (expr == null) { nullSpanBytes } else { packSpan(expr.getSpan()) }
            streams.push(bs + span)
            def rv := exprIndex
            exprIndex += 1
            return rv

        to packExpr(expr) :Bytes:
            return packInt(MASTContext.appendExpr(expr))

        to packExprs(exprs) :Bytes:
            def indices := [for expr in (exprs) MASTContext.packExpr(expr)]
            return packRefs(indices)

        to packNamedArgs(exprs) :Bytes:
            def namedArgs := [for na in (exprs)
                              MASTContext.packExpr(na.getKey()) + MASTContext.packExpr(na.getValue())]
            return packInt(namedArgs.size()) + b``.join(namedArgs)

        to appendPatt(patt) :Int:
            def bs :Bytes := MASTContext.addPatt(patt)
            def span := packSpan(patt.getSpan())
            streams.push(bs + span)
            def rv := pattIndex
            pattIndex += 1
            return rv

        to packPatt(patt) :Bytes:
            return packInt(MASTContext.appendPatt(patt))

        to packPatts(patts) :Bytes:
            def indices := [for patt in (patts) MASTContext.packPatt(patt)]
            return packRefs(indices)

        to packNamedPatt(patt) :Bytes:
            def k := MASTContext.packExpr(patt.getKey())
            def p := MASTContext.packPatt(patt.getValue())
            def e := MASTContext.packExpr(patt.getDefault())
            return k + p + e

        to packNamedPatts(patts) :Bytes:
            def namedPatts := [for patt in (patts)
                               MASTContext.packNamedPatt(patt)]
            return packInt(namedPatts.size()) + b``.join(namedPatts)

        to addExpr(expr) :Bytes:
            if (expr == null) { return b`LN` }
            # traceln(expr.getNodeName())
            return switch (expr.getNodeName()):
                match =="LiteralExpr":
                    switch (expr.getValue()):
                        match ==null:
                            b`LN`
                        match c :Char:
                            # Not likely to fail, so not creating an ejector.
                            def bs := UTF8.encode(c.asString(), null)
                            b`LC$bs`
                        match d :Double:
                            def bs := d.toBytes()
                            b`LD$bs`
                        match i :Int:
                            def zz := if (i < 0) {((i << 1) ^ -1) | 1} else {i << 1}
                            def bs := packInt(zz)
                            b`LI$bs`
                        match s :Str:
                            def bs := packStr(s)
                            b`LS$bs`
                match =="NounExpr":
                    def s := packStr(expr.getName())
                    b`N$s`
                match =="BindingExpr":
                    def s := packStr(expr.getNoun().getName())
                    b`B$s`
                match =="SeqExpr":
                    def exprs := MASTContext.packExprs(expr.getExprs())
                    b`S$exprs`
                match =="MethodCallExpr":
                    def target := MASTContext.packExpr(expr.getReceiver())
                    def verb := packStr(expr.getVerb())
                    def args := MASTContext.packExprs(expr.getArgs())
                    def namedArgs := MASTContext.packNamedArgs(expr.getNamedArgs())
                    b`C$target$verb$args$namedArgs`
                match =="DefExpr":
                    def patt := MASTContext.packPatt(expr.getPattern())
                    def exit_ := MASTContext.packExpr(expr.getExit())
                    def e := MASTContext.packExpr(expr.getExpr())
                    b`D$patt$exit_$e`
                match =="EscapeExpr":
                    def escapePatt := MASTContext.packPatt(expr.getEjectorPattern())
                    def escapeExpr := MASTContext.packExpr(expr.getBody())
                    if (expr.getCatchPattern() == null) {
                        b`e$escapePatt$escapeExpr`
                    } else {
                        def catchPatt := MASTContext.packPatt(expr.getCatchPattern())
                        def catchExpr := MASTContext.packExpr(expr.getCatchBody())
                        b`E$escapePatt$escapeExpr$catchPatt$catchExpr`
                    }
                match =="ObjectExpr":
                    def doc := packStr(expr.getDocstring())
                    def patt := MASTContext.packPatt(expr.getName())
                    def asExpr := MASTContext.packExpr(expr.getAsExpr())
                    def auditors := MASTContext.packExprs(expr.getAuditors())
                    def script := expr.getScript()
                    def methods := MASTContext.packExprs(script.getMethods())
                    def matchers := MASTContext.packExprs(script.getMatchers())
                    b`O$doc$patt$asExpr$auditors$methods$matchers`
                match =="Method":
                    def doc := packStr(expr.getDocstring())
                    def verb := packStr(expr.getVerb())
                    def patts := MASTContext.packPatts(expr.getParams())
                    def namedPatts := MASTContext.packNamedPatts(expr.getNamedParams())
                    def guard := MASTContext.packExpr(expr.getResultGuard())
                    def body := MASTContext.packExpr(expr.getBody())
                    b`M$doc$verb$patts$namedPatts$guard$body`
                match =="Matcher":
                    def patt := MASTContext.packPatt(expr.getPattern())
                    def body := MASTContext.packExpr(expr.getBody())
                    b`R$patt$body`
                match =="AssignExpr":
                    def lvalue := packStr(expr.getLvalue().getName())
                    def rvalue := MASTContext.packExpr(expr.getRvalue())
                    b`A$lvalue$rvalue`
                match =="FinallyExpr":
                    def try_ := MASTContext.packExpr(expr.getBody())
                    def finally_ := MASTContext.packExpr(expr.getUnwinder())
                    b`F$try_$finally_`
                match =="CatchExpr":
                    def try_ := MASTContext.packExpr(expr.getBody())
                    def catchPatt := MASTContext.packPatt(expr.getPattern())
                    def catchExpr := MASTContext.packExpr(expr.getCatcher())
                    b`Y$try_$catchPatt$catchExpr`
                match =="HideExpr":
                    def body := MASTContext.packExpr(expr.getBody())
                    b`H$body`
                match =="IfExpr":
                    def if_ := MASTContext.packExpr(expr.getTest())
                    def then_ := MASTContext.packExpr(expr.getThen())
                    def else_ := MASTContext.packExpr(expr.getElse())
                    b`I$if_$then_$else_`
                match =="MetaStateExpr":
                    b`T`
                match =="MetaContextExpr":
                    b`X`

        to addPatt(patt) :Bytes:
            return switch (patt.getNodeName()):
                match =="FinalPattern":
                    def name := packStr(patt.getNoun().getName())
                    def guard := MASTContext.packExpr(patt.getGuard())
                    b`PF$name$guard`
                match =="IgnorePattern":
                    def guard := MASTContext.packExpr(patt.getGuard())
                    b`PI$guard`
                match =="VarPattern":
                    def name := packStr(patt.getNoun().getName())
                    def guard := MASTContext.packExpr(patt.getGuard())
                    b`PV$name$guard`
                match =="ListPattern":
                    def patts := MASTContext.packPatts(patt.getPatterns())
                    b`PL$patts`
                match =="ViaPattern":
                    def expr := MASTContext.packExpr(patt.getExpr())
                    def innerPatt := MASTContext.packPatt(patt.getPattern())
                    b`PA$expr$innerPatt`
                match =="BindingPattern":
                    def name := packStr(patt.getNoun().getName())
                    b`PB$name`


def makeMASTStream(bytes, withSpans, filename) as DeepFrozen:
    var index := 0
    return object mastStream:
        to exhausted():
            return index >= bytes.size()

        to nextByte(=> FAIL):
            if (mastStream.exhausted()):
                throw.eject(FAIL, `nextByte: Buffer underrun while streaming`)
            def rv := bytes[index]
            index += 1
            return rv

        to nextBytes(count :(Int > 0), => FAIL):
            if (mastStream.exhausted()):
                throw.eject(FAIL, "nextBytes: Buffer underrun while streaming")
            def rv := bytes.slice(index, index + count)
            index += count
            return rv

        to nextDouble(=> FAIL):
            return _makeDouble.fromBytes(mastStream.nextBytes(8), FAIL)

        to nextVarInt(=> FAIL):
            var shift := 0
            var bi := 0
            var cont := true
            while (cont):
                def b := mastStream.nextByte(=> FAIL)
                bi |= (b & 0x7f) << shift
                shift += 7
                cont := (b & 0x80) != 0
            return bi

        to nextInt():
            return mastStream.nextVarInt()

        to nextStr(=> FAIL):
            def size := mastStream.nextInt(=> FAIL)
            if (size == 0):
                return ""
            def via (UTF8.decode) s exit FAIL := mastStream.nextBytes(size)
            return s

        to nextSpan(=> FAIL):
            if (!withSpans):
                return null
            def b := mastStream.nextByte()
            def oneToOne := if (b == 'S'.asInteger()) { true
            } else if (b == 'B'.asInteger()) { false
            } else {throw.eject(FAIL, `Couldn't decode span tag $b`)}
            return _makeSourceSpan(filename, oneToOne,
                                   mastStream.nextInt(),
                                   mastStream.nextInt(),
                                   mastStream.nextInt(),
                                   mastStream.nextInt())
def makeMASTReaderContext(builder) as DeepFrozen:
    def exprs := [].diverge()
    def patts := [].diverge()
    def Expr := builder.getExprGuard()
    def Pattern := builder.getPatternGuard()
    def Ast := builder.getAstGuard()
    return object mastContext:
        to decodeNextTag(stream, => FAIL):
            def readNodeList(guard):
                def nextNode() :guard:
                    return mastContext.exprAt(stream.nextInt())
                return [for _ in (0..!(stream.nextInt())) nextNode()]
            def nextExpr() :Expr:
                return exprs[stream.nextInt(=> FAIL)]
            def nextPattern() :Pattern:
                return patts[stream.nextInt(=> FAIL)]
            def span():
                return stream.nextSpan(=> FAIL)
            def tag := stream.nextByte(=> FAIL)
            if (tag == 'L'.asInteger()):
                def literalTag := stream.nextByte(=> FAIL)
                if (literalTag == 'C'.asInteger()):
                    var buf := b``
                    while (true):
                        buf with= (stream.nextByte(=> FAIL))
                        def via (UTF8.decode) c exit __continue := buf
                        exprs.push(builder.LiteralExpr(c, span()))
                        break
                else if (literalTag == 'D'.asInteger()):
                    exprs.push(builder.LiteralExpr(stream.nextDouble(=> FAIL),
                                                   span()))
                else if (literalTag == 'I'.asInteger()):
                    var i := stream.nextVarInt(=> FAIL) >> 1
                    if ((i & 1) == 0):
                        i ^= -1
                    exprs.push(builder.LiteralExpr(i, span()))
                else if (literalTag == 'N'.asInteger()):
                    exprs.push(builder.LiteralExpr(null, span()))
                else if (literalTag == 'S'.asInteger()):
                    exprs.push(builder.LiteralExpr(stream.nextStr(=> FAIL),
                                                   span()))
                else:
                    throw.eject(FAIL, `Didn't know literal tag $literalTag`)
            else if (tag == 'P'.asInteger()):
                def pattTag := stream.nextByte(=> FAIL)
                if (pattTag == 'F'.asInteger()):
                    def name := stream.nextStr(=> FAIL)
                    def guard := nextExpr()
                    patts.push(builder.FinalPattern(name, guard, span()))
                else if (pattTag == 'I'.asInteger()):
                    def guard := nextExpr()
                    patts.push(builder.IgnorePattern(guard, span()))
                else if (pattTag == 'V'.asInteger()):
                    def name := stream.nextStr(=> FAIL)
                    def guard := nextExpr()
                    patts.push(builder.VarPattern(name, guard, span()))
                else if (pattTag == 'L'.asInteger()):
                    patts.push(readNodeList(Pattern), span())
                else if (pattTag == 'A'.asInteger()):
                    patts.push(builder.ViaPattern(nextExpr(), nextPattern(),
                                                  span()))
                else if (pattTag == 'B'.asInteger()):
                    patts.push(builder.BindingPattern(stream.nextStr(=> FAIL),
                                                      span()))
            else if (tag == 'N'.asInteger()):
                exprs.push(builder.NounExpr(stream.nextStr(=> FAIL), span()))
            else if (tag == 'B'.asInteger()):
                exprs.push(builder.BindingExpr(stream.nextStr(=> FAIL), span()))
            else if (tag == 'S'.asInteger()):
                exprs.push(builder.SeqExpr(readNodeList(Expr), span()))
            else if (tag == 'C'.asInteger()):
                exprs.push(builder.CallExpr(nextExpr(), stream.nextStr(=> FAIL),
                                            readNodeList(Expr), span()))
            else if (tag == 'D'.asInteger()):
                exprs.push(builder.DefExpr(nextPattern(), nextExpr(), nextExpr(),
                                           span()))
            else if (tag == 'e'.asInteger()):
                exprs.push(builder.EscapeExpr(nextPattern(), nextExpr(), null,
                                              null, span()))
            else if (tag == 'E'.asInteger()):
                exprs.push(builder.EscapeExpr(nextPattern(), nextExpr(), nextPattern(),
                                              nextExpr(), span()))
            else if (tag == 'O'.asInteger()):
                exprs.push(builder.ObjectExpr(stream.nextStr(=> FAIL),
                                              nextPattern(),
                                              [nextExpr()] + readNodeList(Expr),
                                              readNodeList(Ast["Method"]),
                                              readNodeList(Ast["Matcher"]),
                                              span()))
            else if (tag == 'M'.asInteger()):
                exprs.push(builder."Method"(stream.nextStr(=> FAIL),
                                          stream.nextStr(=> FAIL),
                                          readNodeList(Pattern),
                                          [for _ in (0..!(stream.nextInt()))
                                           builder.NamedParam(nextExpr(), nextPattern(),
                                                              nextExpr(), null)],
                                          nextExpr(),
                                          nextExpr(),
                                          span()))
            else if (tag == 'R'.asInteger()):
                exprs.push(builder.Matcher(nextPattern(), nextExpr(), span()))
            else if (tag == 'A'.asInteger()):
                exprs.push(builder.AssignExpr(stream.nextStr(=> FAIL), nextExpr(), span()))
            else if (tag == 'F'.asInteger()):
                exprs.push(builder.FinallyExpr(nextExpr(), nextExpr(), span()))
            else if (tag == 'Y'.asInteger()):
                exprs.push(builder.TryExpr(nextExpr(), nextExpr(), span()))
            else if (tag == 'I'.asInteger()):
                exprs.push(builder.IfExpr(nextExpr(), nextExpr(), nextExpr(), span))
            else if (tag == 'T'.asInteger()):
                exprs.push(builder.MetaStateExpr(span()))
            else if (tag == 'X'.asInteger()):
                exprs.push(builder.MetaContextExpr(span()))

def readMAST(bs :Bytes, => filename := "<unknown>",
             => builder := astBuilder, => FAIL) as DeepFrozen:
    if (!bs.startsWith(MAGIC)):
        throw.eject(FAIL, `Wrong magic bytes '${bs.slice(0, MAGIC.size())}'`)
    def version := bs[MAGIC.size()]
    def content := bs.slice(MAGIC.size() + 1)
    def withSpans := if (version == 0) {
        false
    } else if (version == 1) {
        true
    } else {
        throw.eject(FAIL, `Unsupported MAST version $version`)
    }
    def stream := makeMASTStream(content, withSpans, filename)
    def ctx := makeMASTReaderContext(builder)
    while (!stream.exhausted()):
        ctx.decodeNextTag(stream)
    if (ctx.getExprs().size() == 0):
        throw.eject(FAIL, "No expressions in MAST")
    return ctx.getExprs().last()
