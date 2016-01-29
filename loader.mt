# Once this is all hooked up we can rip module support out of the runtime and
# the following line can go away.
exports (main)

def safeScopeBindings :DeepFrozen := [for `&&@n` => v in (safeScope) n => v]

def main(=> _findTyphonFile, => makeFileResource, => typhonEval,
         => currentProcess, => unsafeScope, => unsealException, => Timer,
         => makeStdOut, => bench) as DeepFrozen:

    def valMap := [].asMap().diverge()
    def collectedTests := [].diverge()
    def collectedBenches := [].diverge()
    object testCollector:
        to get(locus):
            return def testBucket(tests):
                for t in tests:
                    collectedTests.push([locus, t])

    object benchCollector:
        to get(locus):
            return def benchBucket(aBench, name :Str):
                collectedBenches.push([`$locus: $name`, aBench])

    def subload(modname, depMap,
                => collectTests := false,
                => collectBenchmarks := false):
        traceln(`Entering $modname`)
        if (modname == "unittest"):
            traceln(`unittest caught`)
            if (collectTests):
                trace(`test collector invoked`)
                return valMap["unittest"] := ["unittest" => testCollector[modname]]
            else:
                return valMap["unittest"] := ["unittest" => fn _ {null}]
        if (modname == "bench"):
            if (collectBenchmarks):
                return valMap["bench"] := ["bench" => benchCollector[modname]]
            else:
                return valMap["bench"] := ["bench" => fn _, _ {null}]

        object loader:
            to "import"(name):
                traceln(`import requested: $name`)
                return valMap[name]
        def fname := _findTyphonFile(modname)
        def loadModuleFile():
            traceln(`reading file $fname`)
            def code := makeFileResource(fname).getContents()
            def mod := when (code) -> {typhonEval(code, safeScopeBindings)}
            depMap[modname] := mod
            return mod
        def mod := depMap.fetch(modname, loadModuleFile)
        return when (mod) ->
            def deps := promiseAllFulfilled([for d in (mod.dependencies())
                                             {traceln(`load $d`);
                                              subload(d, depMap, => collectTests,
                                                      => collectBenchmarks)}])
            when (deps) ->
                valMap[modname] := mod(loader)

    def args := currentProcess.getArguments().slice(2)
    def usage := "Usage: loader run <modname> <args> | loader test <modname>"
    if (args.size() < 1):
        throw(usage)
    switch (args):
        match [=="run", modname] + subargs:
            traceln(`starting load $modname $subargs`)
            def exps := subload(modname, [].asMap().diverge())
            traceln(`loaded $exps`)
            def excludes := ["typhonEval", "_findTyphonFile", "bench"]
            def unsafeScopeValues := [for `&&@n` => &&v in (unsafeScope)
                                      if (!excludes.contains(n))
                                      n => v]
            return when (exps) ->
                def [=> main] | _ := exps
                traceln(`loaded, running`)
                M.call(main, "run", [subargs], unsafeScopeValues)
        match [=="test"] + modnames:
            def someMods := promiseAllFulfilled(
                [for modname in (modnames)
                 subload(modname, [].asMap().diverge(),
                         "collectTests" => true)] +
                [(def testRunner := subload(
                    "testRunner",
                    [].asMap().diverge())),
                 (def tubes := subload(
                     "lib/tubes",
                     [].asMap().diverge()))])
            return when (someMods) ->
                def [=> makeIterFount,
                     => makeUTF8EncodePump,
                     => makePumpTube
                ] | _ := tubes
                def [=> makeAsserter,
                     => makeTestDrain,
                     => runTests] | _ := testRunner

                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout <- flowTo(makeStdOut())

                def asserter := makeAsserter()
                def testDrain := makeTestDrain(stdout, unsealException, asserter)

                when (runTests(collectedTests, testDrain, makeIterFount)) ->
                    def fails := asserter.fails()
                    stdout.receive(`${asserter.total()} tests run, $fails failures$\n`)
                    # Exit code: Only returns 0 if there were 0 failures.
                    for loc => errors in asserter.errors():
                        stdout.receive(`In $loc:$\n`)
                        for error in errors:
                            stdout.receive(`~ $error$\n`)
                    fails.min(1)
        match [=="bench"] + modnames:
            def someMods := promiseAllFulfilled(
                [for modname in (modnames)
                 subload(modname, [].asMap().diverge(),
                         "collectBenchmarks" => true)] +
                [(def benchRunner := subload(
                    "benchRunner",
                    [].asMap().diverge()))])
            return when (someMods) ->
                def [=> runBenchmarks] := benchRunner
                when (runBenchmarks(collectedBenches, bench,
                                    makeFileResource("bench.html"))) ->
                    traceln(`Benchmark report written to bench.html.`)

        match _:
            throw(usage)