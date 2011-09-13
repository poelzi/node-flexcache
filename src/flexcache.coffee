

redis = require 'redis'
buffalo = require 'buffalo'
async = require 'async'
quack = require 'quack-array'
hexy = require('hexy').hexy
hashlib = require('hashlib')

  
class Flexcache
    constructor: (@backend, options, callback) ->
        # set default hasher
        @options = options or {}
        @options.key_prefix ?= "fc_"
        dset = (name, target, def) =>
            switch @options[name]
                when 'all' then @[target] = @hasher_all
                when 'one' then @[target] = @hasher_all
                when 'safe_all' then @[target] = @safe_hasher_all
                when 'safe_one' then @[target] = @safe_hasher_one
                else
                    if typeof @options[name] == 'function' or @options[name] == null
                        @[target] = @options[name]
                    else
                        @[target] = def or @hasher_one
        dset("hash", "hash", @safe_hasher_all)
        dset("key", "key")

    hasher_one: (x) ->
        return hashlib.sha256(JSON.stringify(x))

    hasher_all: (args...) =>
        rv = ""
        if @options.prefix
            rv += @options.prefix
        for arg in args
            if rv
                rv += "|"
            rv += JSON.stringify(arg)
        return hashlib.sha256(rv)

    safe_hasher_one: (x) =>
        return hashlib.sha256(buffalo.serialize([x]))

    safe_hasher_all: (args...) =>
        rv = ""
        #console.log("hashing", args)
        if @options.prefix
            rv += @options.prefix
        rv += hashlib.sha256(buffalo.serialize([args]))
        #console.log("result", rv)
        return rv

    get_key: (args...) =>
        return @options.key_prefix + @key.apply(null, args)
         
    get_hash: (args...) =>
        return @hash.apply(null, args)

    clear: (key, cb) =>
        @backend.clear key, cb

    clear_subkey: (key, subkey, cb) =>
        @backend.clear_subkey key, subkey, cb

    cache: (fn, loptions = {}) =>
        hasher = loptions.hash or @hash
        keyer = loptions.key or @key
        ttl = loptions.ttl or @options.ttl

        wrapper = (wargs..., callback) =>
            if @options.debug > 1
                console.log("try cache call. args:", wargs)
            key_prefix = loptions.key_prefix or @options.key_prefix
            key = key_prefix + keyer(wargs...)
            subkey = hasher(wargs...)
            @backend.get key, subkey, (err, cached) =>
                # undecodeable means non cached
                if err or not cached
                    if @options.debug
                        console.log("cache MISS key:", key, " subkey:", subkey)
                    # call the masked function
                    fn wargs..., (results...) =>
                        if results[0] # error case
                            return callback.apply(null, results)
                        # cache the result
                        @backend.set key, subkey, ttl, results, (err, res) =>
                            # don't care if succeeded
                            if @options.debug
                                console.log("save cache", key, subkey)
                                #console.log(wargs)
                                #console.log(results)
                            # call real callback function
                            callback.apply(null, results)
                    
                else
                    if @options.debug
                        console.log("cache HIT key:", key, " subkey:", subkey)
                        #console.log(cached)
                    callback.apply(null, cached)

        wrapper.get_key = (args...) =>
            keyer = loptions.key or @key
            hasher = loptions.hash or @hash
            key_prefix = loptions.key_prefix or @options.key_prefix
            return key_prefix + keyer.apply(null, args)

        wrapper.get_subkey = (args...) =>
            hasher = loptions.hash or @hash
            return hasher.apply(null, args)

        wrapper.clear = (args...) =>
            callback = args.pop()
            keyer = loptions.key or @key
            key_prefix = loptions.key_prefix or @options.key_prefix
            @clear key_prefix + keyer.apply(null, args), callback # calculate the key like normal parameters

        wrapper.clear_subkey = (args...) =>
            callback = args.pop()
            keyer = loptions.key or @key
            key_prefix = loptions.key_prefix or @options.key_prefix
            hasher = loptions.hash or @hash
            x = keyer.apply(null, args)
            if @options.debug >= 2
                console.log("clear :", key_prefix + keyer.apply(null, args), hasher.apply(null, args))
            @clear_subkey key_prefix + keyer.apply(null, args), hasher.apply(null, args), callback # calculate the key like normal parameters

        return wrapper

module.exports = { Flexcache }
