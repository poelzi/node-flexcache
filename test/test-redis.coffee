{ Flexcache } = require("../flexcache")
{ RedisBackend } = require("../backend/redis")

async = require 'async'

module.exports.TestRedis = (test) ->

    back = new RedisBackend()
    fc = new Flexcache back, ttl:400000

    todo = 0 # calculated 
    got_res = (fnc) ->
        return (args...) ->
            console.log("GOT RES:", args)
            todo--
            fnc.apply(null, args)


    run = 0
    slow = (time, args...) ->
        callback = args.pop()
        setTimeout(() ->
            console.log("RUN SLOW")
            run++
            callback(null, "waited " + time, run, args)
        , 10)


    fast = fc.cache slow
    fast_prefix = fc.cache slow,
        prefix: "X_"
    safe = fc.cache slow,
        hash: fc.safe_hasher_all

    fc.clear 100
    fc.clear 99
    series = [
        (next) ->
            slow 100, got_res next
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
            fc.clear 100, next
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
            fast.clear_subkey 99, 1, next
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
            fast.clear 99, next
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
