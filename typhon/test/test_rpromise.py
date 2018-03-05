from unittest import TestCase
from typhon.rpromise import Handler, Promise, NoopFn, Resolver, PENDING, FULFILLED, REJECTED, CHAINED


class ResolvedFn(object):
    def __init__(self, value):
        self.value = value

    def run(self, resolver):
        resolver.fulfill(self.value)


def resolved(val):
    return Promise(ResolvedFn(val))


class RejectedFn(object):
    def __init__(self, err):
        self.err = err

    def run(self, resolver):
        resolver.reject(self.err)


def rejected(val):
    return Promise(RejectedFn(val))


dummy = object()


class TestPromise(TestCase):
    def testFulfilledState(self):
        """
        Resolved promises propagate their value.
        """
        onFulfilledCalled = [False]

        class H(Handler):
            def onFulfilled(h, result):
                self.assertEqual(result, dummy)
                onFulfilledCalled[0] = True

            def onRejected(h, err):
                self.assertTrue(False)

        p = resolved(dummy)
        self.assertEqual(p.state, FULFILLED)
        p.then(H())
        self.assertEqual(onFulfilledCalled, [True])

        onFulfilledCalled = [False]
        p = Promise(NoopFn())
        p.then(H())
        self.assertEqual(onFulfilledCalled, [False])
        Resolver(p).fulfill(dummy)
        self.assertEqual(onFulfilledCalled, [True])

    def testRejectFulfilled(self):
        """
        Rejection after resolution is a no-op.
        """
        onFulfilledCalled = [False]

        class H(Handler):
            def onFulfilled(h, result):
                self.assertEqual(result, dummy)
                onFulfilledCalled[0] = True

            def onRejected(h, err):
                self.assertTrue(False)

        p = Promise(NoopFn())
        p.then(H())

        r = Resolver(p)
        r.fulfill(dummy)
        r.reject(dummy)
        self.assertTrue(onFulfilledCalled[0])

    def testReject(self):
        """
        Rejected promises propagate their error.
        """
        onRejectedCalled = [False]

        class H(Handler):
            def onFulfilled(h, result):
                self.assertFalse(onRejectedCalled[0])
                self.assertTrue(False)

            def onRejected(h, err):
                self.assertEqual(err, dummy)
                onRejectedCalled[0] = True

        p = rejected(dummy)
        self.assertEqual(p.state, REJECTED)
        p.then(H())
        self.assertTrue(onRejectedCalled[0])

        onRejectedCalled = [False]
        p = Promise(NoopFn())
        p.then(H())
        self.assertFalse(onRejectedCalled[0])
        Resolver(p).reject(dummy)
        self.assertTrue(onRejectedCalled[0])

    def testFulfillRejected(self):
        """
        Resolution after rejection is a no-op.
        """
        onRejectedCalled = [False]

        class H(Handler):
            def onFulfilled(h, result):
                self.assertTrue(False)

            def onRejected(h, err):
                self.assertEqual(err, dummy)
                onRejectedCalled[0] = True

        p = Promise(NoopFn())
        p.then(H())

        r = Resolver(p)
        r.reject(dummy)
        r.fulfill(dummy)
        self.assertTrue(onRejectedCalled[0])
