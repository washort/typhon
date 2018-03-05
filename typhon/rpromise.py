PENDING, FULFILLED, REJECTED, CHAINED = range(4)


class Result(object):
    def __init__(self, value, err):
        self.value = value
        self.err = err


class Resolver(object):
    def __init__(self, target):
        self.target = target
        self.done = False

    def fulfill(self, value):
        # aka 'resolve'
        if self.done:
            return
        self.done = True
        self.target._resolve(value)

    def reject(self, error):
        # aka 'smash'
        if self.done:
            return
        self.done = True
        self.target._reject(error)


class Promise(object):
    def __init__(self, fn):
        self.state = 0
        self.result = None
        self.chain = None
        self.handlers = []
        fn.run(Resolver(self))

    def _resolve(self, result):
        if isinstance(result, Promise):
            if result is self:
                return self._reject(u"A promise cannot be resolved with itself.")
            self.state = CHAINED
            self.chain = result
        else:
            self.state = FULFILLED
            self.result = Result(result, None)
        self.finale()

    def _reject(self, error):
        self.state = REJECTED
        self.result = Result(None, error)
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
                handler.promise._reject(str(e).decode('utf-8'))

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
        return None

    def onRejected(self, result):
        return None


class Fn(object):
    def run(self, resolver):
        pass


NoopFn = Fn
