from functools import wraps

from typhon.nodes import (Call, Def, Escape, FinalPattern, IgnorePattern,
                          Noun, Sequence, Tuple)
from typhon.scope import Scope


def matches(ty):
    def deco(f):
        @wraps(f)
        def inner(node):
            if isinstance(node, ty):
                return f(node)
            return None
        return inner
    return deco


def rewrite(changes, node):
    newestNode = node

    # We'll be done when there are no more changes to make.
    while node is not None:
        for change in changes:
            # If this change results in None, then we will try the next
            # change. If this change results in not-None, then we update our
            # idea of the newest node and start from the beginning.
            node = change(newestNode)
            if node is not None:
                newestNode = node
                break
        else:
            pass
    return newestNode


@matches(Sequence)
def flattenSequence(sequence):
    # The goal is to take nested Sequences and flatten them out so that they
    # are easier to work with.
    changed = False
    rv = []
    for subNode in sequence._l:
        if isinstance(subNode, Sequence):
            rv.extend(subNode._l)
            changed = True
        else:
            rv.append(subNode)

    if not changed:
        return None

    # Do the singleton Sequence check here.
    if len(rv) == 1:
        return rv[0]
    # Copy the list to avoid RPython thinking that we're mutating an immutable
    # list.
    return Sequence(rv[:])


def _isPlainDef(node):
    if not isinstance(node, Def):
        return False
    if not isinstance(node._p, FinalPattern):
        return False
    return node._p._g is None and isinstance(node._v, Noun)


@matches(Sequence)
def simplifyPlainDefs(sequence):
    for i, node in enumerate(sequence._l):
        if _isPlainDef(node):
            # Hit! Unwrap everything and cry a little inside.
            assert isinstance(node, Def)
            p = node._p
            v = node._v
            assert isinstance(p, FinalPattern)
            assert isinstance(v, Noun)
            src = p._n
            dest = v.name
            # Use shadows to rewrite the scope.
            scope = Scope()
            scope.putShadow(src, dest)
            tail = Sequence(sequence._l[i + 1:])
            tail = tail.rewriteScope(scope)
            # Reassemble the sequence, omitting the now-useless Def.
            return Sequence(sequence._l[:i] + tail._l)
    return None

@matches(Sequence)
def elideBareNouns(sequence):
    # Remove any Nouns which are bare and not at the end of Sequences.
    if len(sequence._l) < 2:
        return None

    tail = sequence._l[-1]
    end = len(sequence._l) - 1
    assert end >= 0, "Math is hard"

    rv = []
    changed = False
    for node in sequence._l[:end]:
        if isinstance(node, Noun):
            changed = True
        else:
            rv.append(node)

    if not changed:
        return None

    # Do the singleton Sequence check here.
    if len(rv) == 0:
        return tail
    rv.append(tail)
    return Sequence(rv[:])


@matches(Escape)
def elideUnusedEscape(escape):
    pattern = escape._pattern
    # First, the binding pattern must be a FinalPattern with no guard.
    if isinstance(pattern, FinalPattern) and pattern._g is None:
        name = pattern._n
        # Second, the internal node must not use the ejector.
        if not escape._node.usesName(name):
            return escape._node
    return None


@matches(Escape)
def elideSingleEscape(escape):
    pattern = escape._pattern
    # First, the binding pattern must be a FinalPattern with no guard.
    if not isinstance(pattern, FinalPattern) or pattern._g is not None:
        return None

    name = pattern._n
    node = escape._node

    # Now, the internal node needs to be a Call.
    if not isinstance(node, Call):
        return None

    # We're looking for Calls which fire the ejector. They should also be
    # Calls which don't use the ejector inside any of their other nodes.
    target = node._target
    if not isinstance(target, Noun) or target.name != name:
        return None

    if node._verb.usesName(name) or node._args.usesName(name):
        return None

    # Elide both the Call and the Escape. This only works if the Call was
    # going to pass a single object to the Ejector, but that was probably the
    # case anyway.
    # XXX For now, we'll only finish the optimization if the argument node is
    # a Tuple with a single element.
    args = node._args
    if not isinstance(args, Tuple) or len(args._t) != 1:
        return None

    # XXX For now, refuse to rewrite the catch node. This could be fixed with
    # a little elbow grease.
    if escape._catchNode is not None:
        return None

    return args._t[0]


@matches(Escape)
def narrowEscape(escape):
    pattern = escape._pattern
    # First, the binding pattern must be a FinalPattern with no guard.
    if not isinstance(pattern, FinalPattern) or pattern._g is not None:
        return None

    name = pattern._n
    node = escape._node

    # Now, the internal node needs to be a Sequence.
    if not isinstance(node, Sequence):
        return None

    # We are looking for the first spot in the Sequence (if one exists) where
    # the escape is called unconditionally. After that point, all further
    # expressions are unreachable and can be culled.
    for i, n in enumerate(node._l):
        # Do we invoke the ejector here?
        if isinstance(n, Call):
            target = n._target
            if isinstance(target, Noun) and target.name == name:
                # Yes, we do!
                break
    else:
        return None

    # If it's at the end of the Sequence, then leave it and move on; this is
    # correct enough for now.
    if i + 1 >= len(node._l):
        return None

    # Slice up the Sequence, with a special case for singleton Sequences.
    if i == 0:
        newNode = node._l[0]
    else:
        # Yes, this is the correct slice.
        newNode = Sequence(node._l[:i + 1])

    return Escape(pattern, newNode, escape._catchPattern,
        escape._catchNode)


@matches(Def)
def elideUnusedDef(define):
    pattern = define._p
    # The pattern must be an IgnorePattern with no guard.
    if isinstance(pattern, IgnorePattern) and pattern._g is None:
        # There we go!
        return define._v
    return None


class Optimizer(object):

    def __init__(self, changes):
        self.changes = changes

    def rewrite(self, node):
        return rewrite(self.changes, node)


def optimize(node):
    changes = [
        flattenSequence,
        # This just isn't reasonable as long as we can't rewrite patterns.
        # simplifyPlainDefs,
        elideBareNouns,
        narrowEscape,
        elideSingleEscape,
        elideUnusedDef,
        elideUnusedEscape,
    ]
    f = Optimizer(changes).rewrite
    return node.transform(f)
