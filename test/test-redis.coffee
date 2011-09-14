{ Flexcache } = require("../flexcache")
{ RedisBackend } = require("../backend/redis")
{ MemoryBackend } = require("../backend/memory")

TEST_BACKENDS = [RedisBackend, MemoryBackend]
STRESS_RUNS = 10000

async = require 'async'
garbage = require 'garbage'
inspect = require('eyes').inspector({styles: {all: 'magenta'}})

`function _deepEqual(actual, expected) {
  // 7.1. All identical values are equivalent, as determined by ===.
  if (actual === expected) {
    return true;

  } else if (Buffer.isBuffer(actual) && Buffer.isBuffer(expected)) {
    if (actual.length != expected.length) return false;

    for (var i = 0; i < actual.length; i++) {
      if (actual[i] !== expected[i]) return false;
    }

    return true;

  // 7.2. If the expected value is a Date object, the actual value is
  // equivalent if it is also a Date object that refers to the same time.
  } else if (actual instanceof Date && expected instanceof Date) {
    return actual.getTime() === expected.getTime();

  // 7.3. Other pairs that do not both pass typeof value == 'object',
  // equivalence is determined by ==.
  } else if (typeof actual != 'object' && typeof expected != 'object') {
    return actual == expected;

  // 7.4. For all other Object pairs, including Array objects, equivalence is
  // determined by having the same number of owned properties (as verified
  // with Object.prototype.hasOwnProperty.call), the same set of keys
  // (although not necessarily the same order), equivalent values for every
  // corresponding key, and an identical 'prototype' property. Note: this
  // accounts for both named and indexed properties on Arrays.
  } else {
    return objEquiv(actual, expected);
  }
}

function isUndefinedOrNull(value) {
  return value === null || value === undefined;
}

function isArguments(object) {
  return Object.prototype.toString.call(object) == '[object Arguments]';
}

function objEquiv(a, b) {
  if (isUndefinedOrNull(a) || isUndefinedOrNull(b))
    return false;
  // an identical 'prototype' property.
  if (a.prototype !== b.prototype) return false;
  //~~~I've managed to break Object.keys through screwy arguments passing.
  // Converting to array solves the problem.
  if (isArguments(a)) {
    if (!isArguments(b)) {
      return false;
    }
    a = pSlice.call(a);
    b = pSlice.call(b);
    return _deepEqual(a, b);
  }
  try {
    var ka = Object.keys(a),
        kb = Object.keys(b),
        key, i;
  } catch (e) {//happens when one is a string literal and the other isn't
    return false;
  }
  // having the same number of owned properties (keys incorporates
  // hasOwnProperty)
  if (ka.length != kb.length)
    return false;
  //the same set of keys (although not necessarily the same order),
  ka.sort();
  kb.sort();
  //~~~cheap key test
  for (i = ka.length - 1; i >= 0; i--) {
    if (ka[i] != kb[i])
      return false;
  }
  //equivalent values for every corresponding key, and
  //~~~possibly expensive deep test
  for (i = ka.length - 1; i >= 0; i--) {
    key = ka[i];
    if (!_deepEqual(a[key], b[key])) return false;
  }
  return true;
}
`
gentests = (name, fnc) ->
    for backend in TEST_BACKENDS
        wrapper = (test) ->
            fnc(test, backend)
        dname = name + backend.name
        wrapper.name = dname
        module.exports[dname] = wrapper

noop = () ->


gentests "TestConsistancy", (test, backend) ->

    console.log("test backend", backend.name)

    back = new backend() #RedisBackend()
    fc = new Flexcache back, ttl:400000, debug:2

    todo = 0 # calculated 
    got_res = (fnc) ->
        return (args...) ->
            todo--
            fnc.apply(null, args)


    run = 0
    slow = (time, args..., callback) ->
        setTimeout(() ->
            run++
            console.log("RUN SLOW",run, "args",time,  args)
            callback(null, "waited " + time, run, args)
        , 10)


    fast = fc.cache slow, {name:"slow"}
    fast_prefix = fc.cache slow,
        name: "slow2"
    safe = fc.cache slow,
        hash: fc.safe_hasher_all
        name: "slow3"

    fc.clear_group fc.get_group(100)
    fc.clear_group fc.get_group(99)
    series = [
        (next) ->
            slow 100, got_res next
        ,
        (next) ->
            fast 100, got_res (err) ->
                test.equal(run, 2, "cache was hit 1")
                next err
        ,
        (next) ->
            # must hit cache
            fast 100, got_res (err, waited, run) ->
                test.equal(run, 2, "cache was not hit 2")
                next err
        ,
        (next) ->
            # clear the cache
            fast.clear_group 100, next
        ,
        (next) ->
            fast 100, got_res (err, waited, run) ->
                test.equal(run, 3, "cache was hit 3")
                next null
        ,
        (next) ->
            fast 99, got_res (err, waited, run) ->
                test.equal(run, 4, "cache was hit 4")
                next null
        ,
        # subkey tests
        (next) ->
            fast 99, 1, got_res (err, waited, run) ->
                test.equal(run, 5, "cache was hit 5")
                next null
        ,
        (next) ->
            fast 99, 2, got_res (err, waited, run) ->
                test.equal(run, 6, "cache was hit 6")
                next null
        ,
        (next) ->
            # clear the cache
            fast.clear_hash 99, 1, next
        ,
        (next) ->
            fast 99, 2, got_res (err, waited, run) ->
                test.equal(run, 6, "cache was hit 7")
                next null
        ,
        (next) ->
            fast 99, 1, got_res (err, waited, run) ->
                test.equal(run, 7, "cache was hit 8")
                next null
        ,
        (next) ->
            fast 99, "1", got_res (err, waited, run) ->
                test.equal(run, 8, "cache was hit 9")
                next null
        ,
        (next) ->
            safe 99, new Buffer([1,2]), got_res (err, waited, run) ->
                test.equal(run, 9, "cache was hit 10")
                next null
        ,
        (next) ->
            safe 99, new Buffer([1,2]), got_res (err, waited, run) ->
                test.equal(run, 9, "cache was hit 11")
                next null
        ,
        (next) ->
            # clear the cache
            fast.clear_group 99, next
        ,
        (next) ->
            safe 99, new Buffer([1,2]), got_res (err, waited, run) ->
                test.equal(run, 10, "cache was hit 12")
                next null
        ,
        (next) ->
            fast_prefix 99, "1", got_res (err, waited, run) ->
                test.equal(run, 11, "cache was hit 13")
                next null
        ,
        ]
    todo = series.length - 3
    async.series series, (err) ->
        test.equal(err, null, "error thrown")
        test.equal(todo, 0, "todo is not right")
        back.close()
        test.done()


module.exports.StressBson = (test) ->
    test.done()
    return
    garbage = require('garbage')
    buffalo = require('buffalo')
    for i in [0...5000]
        x = [garbage(100)]
        test.deepEqual(x, buffalo.parse(buffalo.serialize(x)))
    test.done()

module.exports.TestHashes = (test) ->
    found_keys = {}
    fc = new Flexcache true
    hasher = null
    for hasher in [fc.safe_hasher_all, fc.hasher_all]
        found_keys = {}
        
        unique = (value) ->
            test.equal(found_keys[value], undefined, "hash was already found: " + value)
            found_keys[value] = true
        
        for i in [0...100]
            unique(hasher(i, null, ["bla"], {a:"b"}, new Buffer([0,1])))

        for i in [0...100]
            unique(hasher(i))
        for i in [0...100]
            unique(hasher(0, i))
        for i in [0...100]
            unique(hasher(null, i))


    for hasher in [fc.safe_hasher_one, fc.hasher_one]
        found_keys = {}
        
        unique = (value) ->
            test.equal(found_keys[value], undefined, "hash was already found")
            found_keys[value] = true
        
        for i in [0...100]
            unique hasher(i, null, ["bla"], {a:"b"}, new Buffer([0,1]))
        unique hasher "one", 1
        for i in [0...100]
            test.ok(found_keys[hasher("one", i)], "key should be cached: " + hasher)
    test.done()

module.exports.TestAPI = (test) ->
    back = new MemoryBackend()
    fc = new Flexcache back
    test_flex = () ->
        new Flexcache()
    test.throws(test_flex, Error, "not without backend")

    test_noname = () ->
        fc.cache(noop)
    test.throws(test_noname, Error, "name missing on anonymous function")

    back.close()
    test.done()

gentests "Stress", (test, backend) ->

    RUNS = STRESS_RUNS

    run = () ->
    back = new backend()
    options =
        ttl:100 * 1000 # 100 secs should be enough
        key: () ->
            return "stress"
        debug: false

    fc = new Flexcache back, options

    todo = 0 # calculated 
    got_res = (fnc) ->
        return (args...) ->
            console.log("GOT RES:", args)
            todo--
            fnc.apply(null, args)

    run = 0

    randlist = (num, runme) ->
        rvn = (Math.random()*num)
        runme ?= run++
        rv = [runme]
        for i in [0..rvn]
            rv.push(garbage(100))
        rv


    slow = (args..., callback) ->
        setTimeout(() ->
            rv = [null].concat randlist(5, args[0])
            callback.apply(null, rv)
        , 0)


    fast = fc.cache slow, name:"slow"

    start = new Date().getTime()

    queue = async.queue (task, callback) ->

        args = randlist(5)

        check = (err, res...) ->
            first_rv = res
            test.equal(err, null)
            test.ok(res)

            check2 = (err, second_rv...) ->
                test.ok(second_rv)
                if not _deepEqual(second_rv, first_rv)
                    console.log("args:", args)
                    console.log("hash group:")
                    inspect(fast.get_group.apply(null, args))
                    console.log("hash:")
                    inspect(fast.get_hash.apply(null, args))
                    console.log("diff detected:")
                    console.log("is:", second_rv)
                    console.log("should:", first_rv)
                    #process.nextTick(process.exit)
                    #test.done()
                    test.ok(false)
                test.deepEqual(second_rv, first_rv)
                callback()

            fast.apply null, args.concat([check2])

        fast.apply null, args.concat([check])


    , 10
    
    for i in [0...RUNS]
        queue.push {}
    queue.drain = (err, done) ->
        back.close()
        took = (new Date().getTime() - start)/1000
        console.log("took:", took, "s  req/sec:", RUNS/took)
        test.done()

