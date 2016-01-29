import "lib/continued" =~ [=> continued :DeepFrozen]
import "unittest" =~ [=> unittest]
exports (makePiEntropy)


def makePiEntropy() as DeepFrozen:
    def pi := continued.pi().extractDigits(2)
    # Move past the first digit (3)
    pi.produceDigit(null)

    return object piEntropy:
        to getAlgorithm() :Str:
            return "π"

        to getEntropy():
            return [1, pi.produceDigit(null)]


def testPiEntropy(assert):
    # Vectors generated by, well, pi.
    # 3.14159...
    # -.125
    # =.01659...
    def x := makePiEntropy()
    assert.equal(x.getEntropy()[1], 0x0) # 0.5
    assert.equal(x.getEntropy()[1], 0x0) # 0.25
    assert.equal(x.getEntropy()[1], 0x1) # 0.125
    assert.equal(x.getEntropy()[1], 0x0) # 0.0625
    assert.equal(x.getEntropy()[1], 0x0) # 0.03125

unittest([testPiEntropy])
