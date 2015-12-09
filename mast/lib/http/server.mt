imports => unittest
exports (makeHTTPEndpoint)

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

def [=> UTF8 :DeepFrozen] | _ := import.script("lib/codec/utf8")
def [=> makeMapPump :DeepFrozen,
     => makePumpTube :DeepFrozen,
     => chain :DeepFrozen,
] := import("lib/tubes", [=> unittest])
def [=> makeEnum :DeepFrozen] | _ := import("lib/enum", [=> unittest])
def [=> PercentEncoding :DeepFrozen] | _ := import("lib/percent",
                                                   [=> unittest])

def [RequestState :DeepFrozen,
     REQUEST :DeepFrozen,
     HEADER :DeepFrozen,
     BODY :DeepFrozen] := makeEnum(["request", "header", "body"])

def makeRequestPump() as DeepFrozen:
    var state :RequestState := REQUEST
    var buf :Bytes := b``
    var pendingRequest := null
    var pendingRequestLine := null
    var pendingHeaders := null

    return object requestPump:
        to started():
            null

        to progressed(amount):
            null

        to stopped(_):
            null

        to received(bytes :Bytes) :List:
            # traceln(`received bytes $bytes`)
            buf += bytes

            var shouldParseMore :Bool := true

            while (shouldParseMore):
                escape badParse:
                    shouldParseMore := requestPump.parse(badParse)
                catch _:
                    return [null]

            if (pendingRequest != null):
                def rv := [pendingRequest]
                pendingRequest := null
                return rv

            return []

        to parse(ej) :Bool:
            # Return whether more parsing can take place.
            # Eject if the parse fails.

            switch (state):
                match ==REQUEST:
                    if (buf.indexOf(b`$\r$\n`) == -1):
                        return false

                    # XXX it'd be swell if these were subpatterns
                    def b`@{via (UTF8.decode) verb} @{via (PercentEncoding.decode) uri} HTTP/1.1$\r$\n@t` exit ej := buf
                    pendingRequestLine := [verb, uri]
                    pendingHeaders := [].asMap()
                    state := HEADER
                    buf := t
                    return true

                match ==HEADER:
                    if (buf.indexOf(b`$\r$\n`) == -1):
                        return false

                    if (buf =~ b`$\r$\n@t`):
                        state := BODY
                        buf := t
                        return true

                    def b`@{via (UTF8.decode) header}:@{via (UTF8.decode) value}$\r$\n@t` exit ej := buf
                    pendingHeaders |= [header => value.trim()]
                    buf := t
                    return true

                match ==BODY:
                    state := REQUEST
                    pendingRequest := [pendingRequestLine, pendingHeaders]
                    return true


def makeRequestTube() as DeepFrozen:
    return makePumpTube(makeRequestPump())


def statusMap :Map[Int, Str] := [
    200 => "OK",
    301 => "Moved Permanently",
    303 => "See Other",
    307 => "Temporary Redirect",
    400 => "Bad Request",
    404 => "Not Found",
]


def makeResponsePump() as DeepFrozen:
    return object responsePump:
        to started():
            null

        to progressed(amount):
            null

        to stopped(_):
            null

        to received(response):
            def [statusCode, headers, body] := response
            def statusDescription := statusMap.fetch(statusCode,
                                                     "Unknown Status")
            def status := `$statusCode $statusDescription`
            var rv := [b`HTTP/1.1 $status$\r$\n`]
            for header => value in headers:
                def headerLine := `$header: $value`
                rv with= (b`$headerLine$\r$\n`)
            rv with= (b`$\r$\n`)
            rv with= (body)
            return rv


def makeResponseTube() as DeepFrozen:
    return makePumpTube(makeResponsePump())


def serverHeader :Map[Str, Str] := [
    "Server" => "Monte (Typhon) (.i ma'a tarci pulce)",
]

def processorWrapper(app) as DeepFrozen:
    def wrappedProcessor(request):
        # null means a bad request that was unparseable.
        def [statusCode, headers, body] := if (request == null) {
            # We must close the connection after a bad request, since a parse
            # failure leaves the request tube in an indeterminate state.
            [400, ["Connection" => "close"], []]
        } else {app(request)}
        return [statusCode, headers | serverHeader, body]
    return wrappedProcessor


def makeProcessingTube(app) as DeepFrozen:
    return makePumpTube(makeMapPump(processorWrapper(app)))


def makeHTTPEndpoint(endpoint) as DeepFrozen:
    return object HTTPEndpoint:
        to listen(processor):
            def responder(fount, drain):
                chain([
                    fount,
                    makeRequestTube(),
                    makeProcessingTube(processor),
                    makeResponseTube(),
                    drain,
                ])
            endpoint.listen(responder)
