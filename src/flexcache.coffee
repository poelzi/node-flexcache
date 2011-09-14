###
Flexcache

Copyright (c) 2011 Daniel Poelzleithner

BSD License
###

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
        @options.group_prefix ?= "fc_"
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
        dset("group", "group")

    hasher_one: (x) ->
        return hashlib.sha256(JSON.stringify(x))

    hasher_all: (args...) =>
        rv = ""
        if @options.prefix
            rv += @options.prefix
        rv += hashlib.sha256(JSON.stringify(arg))
        return rv

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

    get_group: (args...) =>
        return @options.group_prefix + @group.apply(null, args)
         
    get_hash: (args...) =>
        return @hash.apply(null, args)

    clear_group: (group, cb) =>
@backend.clear_group group, cb

    clear_hash: (group, hash, cb) =>
        @backend.clear_hash group, hash, cb

    cache: (fn, loptions = {}) =>
        hasher = loptions.hash or @hash
        grouper = loptions.group or @group
        ttl = loptions.ttl or @options.ttl

        wrapper = (wargs..., callback) =>
            if @options.debug > 1
                console.log("try cache call. args:", wargs)
            group_prefix = loptions.group_prefix or @options.group_prefix
            group = group_prefix + grouper(wargs...)
            hash = hasher(wargs...)
            @backend.get group, hash, (err, cached) =>
                # undecodeable means non cached
                if err or not cached
                    if @options.debug
                        console.log("cache MISS group:", group, " hash:", hash)
                    # call the masked function
                    fn wargs..., (results...) =>
                        if results[0] # error case
                            return callback.apply(null, results)
                        # cache the result
                        @backend.set group, hash, ttl, results, (err, res) =>
                            # don't care if succeeded
                            if @options.debug
                                console.log("save cache", group, hash)
                                #console.log(wargs)
                                #console.log(results)
                            # call real callback function
                            callback.apply(null, results)
                    
                else
                    if @options.debug
                        console.log("cache HIT group:", group, " hash:", hash)
                        #console.log(cached)
                    callback.apply(null, cached)

        wrapper.get_group = (args...) =>
            grouper = loptions.group or @group
            hasher = loptions.hash or @hash
            group_prefix = loptions.group_prefix or @options.group_prefix
            return group_prefix + grouper.apply(null, args)

        wrapper.get_hash = (args...) =>
            hasher = loptions.hash or @hash
            return hasher.apply(null, args)

        wrapper.clear_group = (args...) =>
            callback = args.pop()
            grouper = loptions.group or @group
            group_prefix = loptions.group_prefix or @options.group_prefix
            @clear_group group_prefix + grouper.apply(null, args), callback # calculate the key like normal parameters

        wrapper.clear_hash = (args...) =>
            callback = args.pop()
            grouper = loptions.group or @group
            group_prefix = loptions.group_prefix or @options.group_prefix
            hasher = loptions.hash or @hash
            x = grouper.apply(null, args)
            if @options.debug >= 2
                console.log("clear :", group_prefix + grouper.apply(null, args), hasher.apply(null, args))
            @clear_hash group_prefix + grouper.apply(null, args), hasher.apply(null, args), callback # calculate the key like normal parameters

        return wrapper

module.exports = { Flexcache }
