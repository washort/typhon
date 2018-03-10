from rpython.rlib.objectmodel import specialize
PENDING, FULFILLED, REJECTED, CHAINED = range(4)


class Result(object):
    def __init__(self, value, err, promise):
        self.value = value
        self.err = err
        self.promise = promise


class Resolver(object):
    def __init__(self, target):
        self.target = target
        self.done = False

    @specialize.call_location()
    def fulfill(self, value):
        # aka 'resolve'
        if self.done:
            return
        self.done = True
        self.target._resolve((value, None, None))

    def reject(self, error):
        # aka 'smash'
        if self.done:
            return
        self.done = True
        self.target._reject((None, error, None))

    def chain(self, p):
        if self.done:
            return
        self.done = True
        self.target._resolve((None, None, p))


class Promise(object):
    def __init__(self, fn):
        self.state = 0
        self.handlers = []
        fn.run(Resolver(self))

    @specialize.call_location()
    def _resolve(self, result):
        if result[2]:
            if result[2] is self:
                return self._reject((None,
                           u"A promise cannot be resolved with itself.",
                           None))
            self.state = CHAINED
        else:
            self.state = FULFILLED
        self.setResult(result)
        self.finale()

    def _reject(self, error):
        self.state = REJECTED
        self.setResult(error)
        self.finale()

    def finale(self):
        for h in self.handlers:
            self._handle(h)
        del self.handlers[:]

    def _handle(self, handler):
        while self.state == CHAINED and self.getResult()[2] is not None:
            self = self.getResult()[2]
        if self.state == PENDING:
            self.handlers.append(handler)
        else:
            try:
                if self.state == FULFILLED:
                    handler.promise._resolve(
                        handler.onFulfilled(self.getResult()))
                else:
                    handler.promise._resolve(
                        handler.onRejected(self.getResult()))
            except Exception as e:
                handler.promise._reject((None, str(e).decode('utf-8'), None))

    def then(self, handler):
        self._handle(handler)
        return handler.promise


_promiseTypes = []
def makeNewPromiseType(name):
    import textwrap
    exec textwrap.dedent("""
    class _Promise(Promise):
        def __init__(self, fn):
            Promise.__init__(self, fn)
            self.result_{0} = (None, None, None)
        @specialize.call_location()
        def setResult(self, result):
            self.result_{0} = result
        @specialize.call_location()
        def getResult(self):
            return self.result_{0}
""".format(name))
    _promiseTypes.append(_Promise)
    return _Promise


class Handler(object):
    def __init__(self):
        self.promise = Promise(NoopFn())

    def onFulfilled(self, result):
        return (None, None, None)

    def onRejected(self, result):
        return (None, None, None)


class MonteResolverHandler(Handler):
    def __init__(self, monteResolver):
        Handler.__init__(self)
        self.monteResolver = monteResolver

    def onFulfilled(self, result):
        self.monteResolver.resolve(result.value)

    def onRejected(self, result):
        from typhon.objects.data import StrObject
        self.monteResolver.smash(StrObject(result.err))


class Fn(object):
    def run(self, resolver):
        pass


NoopFn = Fn
