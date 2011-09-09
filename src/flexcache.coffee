

redis = require 'redis'
buffalo = require 'buffalo'
async = require 'async'
quack = require 'quack-array'

  
class Flexcache
    constructor: (@backend, options, callback) ->
        # set default hasher
        @options = options or {}
        #console.log("ieu")
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
        return JSON.stringify(x)

    hasher_all: (args...) =>
        rv = ""
        if @options.prefix
            rv += @options.prefix
        for arg in args
            if rv
                rv += "|"
            rv += JSON.stringify(arg)
        return rv

    safe_hasher_one: (x) ->
        return JSON.stringify(x)

    safe_hasher_all: (args...) =>
        rv = ""
        if @options.prefix
            rv += @options.prefix
        rv += buffalo.serialize(args)
        return rv

    clear: (key, cb) =>
        @backend.clear key, cb

    clear_subkey: (key, subkey, cb) =>
        @backend.clear_subkey key, subkey, cb

    cache: (fn, loptions) =>
        loptions ?= {}
        hasher = loptions.hash or @hash
        keyer = loptions.key or @key
        ttl = loptions.ttl or @options.ttl

        rv = (args...) =>
            callback = args.pop()
            real_arguments = arguments

            key = keyer.apply(null, args)
            subkey = hasher.apply(null, args)
            @backend.get key, subkey, (err, cached) =>
                # undecodeable means non cached
                if err or not cached
                    fn.apply(null, args.concat [ (args...) =>
                        if args[0] # error case
                            return callback.apply(null, args)
                        # cache the result
                        @backend.set key, subkey, ttl, args, (err, res) ->
                            # don't care if succeeded
                            callback.apply(null, args)
                    ])
                else
                    callback.apply(null, cached)

        rv.clear = (args...) =>
            if typeof(args[0]) == "string"
                @clear args[0]
            else
                callback = args.pop()
                keyer = loptions.key or @key
                @clear keyer.apply(null, args), callback # calculate the key like normal parameters

        rv.clear_subkey = (args...) =>
            if typeof(args[0]) == "string" and typeof(args[1]) == "string"
                @clear args[0], args[1]
            else
                callback = args.pop()
                keyer = loptions.key or @key
                hasher = loptions.hash or @hash
                x = keyer.apply(null, args)
                @clear_subkey keyer.apply(null, args), hasher.apply(null, args), callback # calculate the key like normal parameters

        return rv

module.exports = { Flexcache }
