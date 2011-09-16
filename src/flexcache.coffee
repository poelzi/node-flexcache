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
assert = require('assert')
{ EventEmitter } = require('events')

  
class Flexcache
    constructor: (@backend, options, callback) ->
        # set default hasher
        if not @backend
            throw new Error("backend missing")
        @options = options or {}
        @options.group_prefix ?= "fc_"
        @options.max_object_size ?= 500 * 1024
        @used_names = {}
        dset = (name, target, def) =>
            switch @options[name]
                when 'all' then @[target] = @hasher_all
                when 'one' then @[target] = @hasher_one
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
        return JSON.stringify(x)

    hasher_all: (args...) =>
        return JSON.stringify(args)

    safe_hasher_one: (x) =>
        return hashlib.sha256(buffalo.serialize([x]))

    safe_hasher_all: (args...) =>
        return hashlib.sha256(buffalo.serialize(args))

    get_group: (args...) =>
        return @options.group_prefix + @group.apply(null, args)
         
    get_hash: (args...) =>
        return @hash.apply(null, args)

    get_name_hash: (name, args...) =>
        return name + "_" + @hash.apply(null, args)

    get_cache: (group, hash, cb) =>
        @backend.get group, hash, {}, (err, cached) =>
            if err
                cb(null)
            else
                cb(cached)

    clear_group: (group, cb) =>
        @backend.clear_group group, cb

    clear_hash: (group, hash, cb) =>
        @backend.clear_hash group, hash, cb

    calculate_size: (obj) ->
        if typeof(obj) == "string" or Buffer.isBuffer(obj)
            return obj.length
        else if typeof(obj) == "object"
            rv = 0
            for own value, key of obj
                rv += calculate_size(value)
                rv += calculate_size(key)
            return rv
        else if obj.length
            return obj.length
        return 0

    cache: (fn, loptions = {}) =>
        hasher = loptions.hash or @hash
        grouper = loptions.group or @group
        ttl = loptions.ttl or @options.ttl
        hash_name = loptions.name or fn.name

        # test validity of options
        if not hash_name
            throw new Error("Flexcachecname missing in options on anonymous function")
        if @used_names[hash_name] and not loptions.multi
            throw new Error("Name is already in use and multi is false")
        @used_names[hash_name] = true

        # prepare event emitter if set
        if loptions.emitter
            if typeof(loptions.emitter) == 'boolean'
                emitter = EventEmitter
            else if typeof(loptions.emitter) == 'function'
                emitter = loptions.emitter


        wrapper = (wargs..., callback) =>
            # in case no callback was defined, push it back to the arguments list
            if typeof(callback) != 'function'
                wargs.push(callback)
                callback = undefined
            if @options.debug > 1
                console.log("try cache call. args:", wargs)

            # calculate group and hash keys
            group_prefix = loptions.group_prefix or @options.group_prefix
            group = group_prefix + grouper(wargs...)
            hash = hash_name + "_" + hasher(wargs...)
            # create event emitter return value
            if emitter
                ee = new emitter wargs..., callback
            
            opt = { serializer: loptions.serializer or @options.serializer}
            @backend.get group, hash, opt, (err, cached) =>
                # undecodeable means non cached
                if err or not cached
                    # MISS
                    if @options.debug
                        console.log("cache MISS group:", group, " hash:", hash)
                    # call the masked function
                    if emitter
                        total_buffer = []
                        total_size = 0
                        over_limit = false
                        # call the masked function.
                        realee = fn wargs...
                        if @options.debug >= 3
                            console.log("real function returned:", realee)
                        realee.on 'data', (data) =>
                            ee.emit 'data', data
                            if not over_limit
                                total_buffer.push(data)
                                #total_size += @calculate_size(data)
                                over_limit = total_size/2 > @options.max_object_size
                        realee.on 'end', () =>
                            # save result in cache
                            #total_buffer.push(data)
                            opt = ttl:ttl, max_object_size:@options.max_object_size, debug_serializer:@options.debug_serializer
                            @backend.set group, hash, total_buffer, opt, (err, res) =>
                                if @options.debug
                                    console.log("flexcache save cache:", group, hash, "err:", err)
                                    if @options.debug >= 3
                                        console.log("flexcache data:")
                                        console.log(total_buffer)
                                ee.emit 'end'


                    else
                        fn wargs..., (results...) =>
                            # we save the result as it is, and therefore the error argument as well
                            if results[0] # error case
                                return callback.apply(null, results)
                            # cache the result
                            opt = ttl:ttl, max_object_size:@options.max_object_size
                            @backend.set group, hash, results, opt, (err, res) =>
                                # don't care if succeeded
                                if @options.debug
                                    console.log("save cache", group, hash)
                                    #console.log(wargs)
                                    #console.log(results)
                                # call real callback function
                                if callback
                                    callback.apply(null, results)
                    
                else
                    # HIT
                    if @options.debug
                        console.log("flexcache HIT group:", group, " hash:", hash)
                        if @options.debug >= 3
                            console.log("data:")
                            console.log(cached)
                            console.log("####")
                        #console.log(cached)
                    if not emitter
                        if callback
                            callback.apply(null, cached)
                    else
                        # handle event emmitter
                        atest = () ->
                            cached.length
                        adata = (callback) ->
                            mydata = cached.splice(0,1)
                            #console.log(mydata)
                            ee.emit 'data', mydata[0]
                            setTimeout callback, 0
                        aend = () ->
                            ee.emit('end')
                        async.whilst(atest, adata, aend)
            ee or null

        wrapper.get_group = (args...) =>
            grouper = loptions.group or @group
            group_prefix = loptions.group_prefix or @options.group_prefix
            return group_prefix + grouper.apply(null, args)

        wrapper.get_hash = (args...) =>
            hasher = loptions.hash or @hash
            return hash_name + "_" + hasher.apply(null, args)

        wrapper.clear_group = (args...) =>
            callback = args.pop()
            grouper = loptions.group or @group
            group_prefix = loptions.group_prefix or @options.group_prefix
            if @options.debug
                console.log("clear group:", group_prefix + grouper.apply(null, args), hasher.apply(null, args))
            @clear_group group_prefix + grouper.apply(null, args), callback # calculate the key like normal parameters

        wrapper.clear_hash = (args...) =>
            callback = args.pop()
            grouper = loptions.group or @group
            group_prefix = loptions.group_prefix or @options.group_prefix
            hasher = loptions.hash or @hash
            x = grouper.apply(null, args)
            if @options.debug
                console.log("clear hash:", group_prefix + grouper.apply(null, args), hash_name + "_" + hasher.apply(null, args))
            @clear_hash group_prefix + grouper.apply(null, args), hash_name + "_" + hasher.apply(null, args), callback # calculate the key like normal parameters

        return wrapper

module.exports = { Flexcache }
