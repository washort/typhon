import "lib/json" =~ [=> JSON :DeepFrozen]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/tubes" =~ [
    => makeUTF8DecodePump :DeepFrozen,
    => makeUTF8EncodePump :DeepFrozen,
    => makePumpTube :DeepFrozen,
]
exports (main)

def makeCollector() as DeepFrozen:
    def [p, r] := Ref.promise()
    def buf := [].diverge()
    object outputCollector:
        to flowingFrom(fount) :Any:
            return outputCollector
        to receive(item) :Void:
            buf.push(item)
        to progress(amount :Double) :Void:
            null
        to flowStopped(reason :Str):
            r.resolve("".join(buf))
        to flowAborted(reason :Str):
            r.smash(reason)
    return [p, outputCollector]

def main(argv, => makeProcess, => makeFileResource, => currentProcess, => makeStdErr) as DeepFrozen:
    if (argv.size() != 2):
        throw("Usage: mt-bake <prefetch-scripts-dir> <project-directory>")
    def [fetchersDir, projDir] := argv
    def fetchers := ["git" => UTF8.encode(fetchersDir + "/bin/nix-prefetch-git", throw)]

    def fetchDep(url :Bytes, fetcher :Bytes):
        def env := currentProcess.getEnvironment()
        def [gitInfo, gitInfoCollector] := makeCollector()
        def out := makePumpTube(makeUTF8DecodePump())
        out.flowTo(gitInfoCollector)
        def proc := makeProcess(
            fetcher, [fetcher.split(b`/`).last(), url], env.with(b`PRINT_PATH`, b`1`),
            "stdoutDrain" => out,
            "stderrDrain" => makeStdErr())
        return when (def pi := proc.wait(), gitInfo) ->
            if (pi.exitStatus() != 0):
                throw(`Process failed: $gitInfo`)
            def lines := gitInfo.split("\n")
            def depPath := lines[lines.size() - 2]
            def via (JSON.decode) data := "".join(lines.slice(0, lines.size() - 2))
            def ["rev" => commitStr, "sha256" => hashStr] | _ := data
            [depPath, commitStr, hashStr]

    def readJSONFile(fname):
        return when (def input := makeFileResource(fname).getContents()) ->
            def via (UTF8.decode) via (JSON.decode) data := input
            data
    return when (def data := readJSONFile(projDir + "/mt.json")) ->
        def deps := [].diverge()
        def depUrlsSeen := [for [_, dv] in (deps) dv["url"]].asSet().diverge()
        def srcDepExprs := []
        def depExprs := []
        def sources := [data["name"] => [
            "type" => "local",
            "path" => projDir]].diverge()
        def packages := [].asMap().diverge()
        def depNamesSet := [data["name"]].asSet().diverge()
        def genName(var name):
            var i := 0
            while (depNamesSet.contains(name)):
                name := `${name}_$i`
            depNamesSet.include(name)
            return name
        def collectDep(depname, dep):
            deps.push([depname, dep])
            def depType := dep.fetch("type", fn{"git"})
            def depInfo := fetchDep(
                UTF8.encode(dep["url"], throw),
                fetchers[depType])
            return when (depInfo) ->
                def [depPath, commitStr, hashStr] := depInfo
                sources[depname] := [
                    "url" => dep["url"],
                    "type" => depType,
                    "commit" => commitStr,
                    "hash" => hashStr]
                when (def subdata := readJSONFile(depPath + "/mt.json")) ->
                    def subdepVows := [].diverge()
                    def subdepNames := [].diverge()
                    for k => v in (subdata.fetch("dependencies", fn {[].asMap()})):
                        def url := v["url"]
                        if (!depUrlsSeen.contains(url)):
                            def n := genName(k)
                            depUrlsSeen.include(url)
                            subdepVows.push(collectDep(n, v))
                            subdepNames.push(n)
                    packages[subdata["name"]] := [
                        "source" => depname,
                        "dependencies" => subdepNames.snapshot(),
                        "entrypoint" => null,
                        "paths" => subdata["paths"]]
                    promiseAllFulfilled(subdepVows)
        when (promiseAllFulfilled([
                for k => v in (data.fetch("dependencies",
                                          fn {[].asMap()}))
                collectDep(k, v)])) ->
            packages[data["name"]] := [
                "source" => data["name"],
                "dependencies" => [for d in (deps) d[0]],
                "entrypoint" => data.fetch("entrypoint", fn {null}),
                "paths" => data["paths"]]
            def via (JSON.encode) via (UTF8.encode) outBytes := [
                "sources" => sources.snapshot(),
                "packages" => packages.snapshot(),
                "entrypoint" => data["name"]]
            def outFname := projDir + "/mt-lock.json"
            when (makeFileResource(outFname).setContents(outBytes)) ->
                0

