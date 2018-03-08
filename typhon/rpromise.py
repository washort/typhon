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
        self.result = (None, None, None)
        self.chain = None
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
        self.result = result
        self.finale()

    def _reject(self, error):
        self.state = REJECTED
        self.result = error
        self.finale()

    def finale(self):
        for h in self.handlers:
            self._handle(h)
        del self.handlers[:]

    def _handle(self, handler):
        while self.state == CHAINED and self.chain is not None:
            self = self.chain
        if self.state == PENDING:
            self.handlers.append(handler)
        else:
            try:
                if self.state == FULFILLED:
                    handler.promise._resolve(
                        handler.onFulfilled(self.result))
                else:
                    handler.promise._resolve(
                        handler.onRejected(self.result))
            except Exception as e:
                handler.promise._reject((None, str(e).decode('utf-8'), None))

    def then(self, handler):
        if handler.promise is not None:
            raise ValueError("Pass fresh handler instances to Promise.then")
        handler.promise = Promise(NoopFn())
        self._handle(handler)
        return handler.promise


class Handler(object):
    def __init__(self):
        self.promise = None

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
