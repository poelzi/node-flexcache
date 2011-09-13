{ Backend } = require './base'


class MemoryBackend extends Backend
    constructor: (options) ->
        @cache = {}
        @options = options or {}

        super @options

    _call: (fn, args...) =>
        if @options.async
            process.nextTick () ->
                fn.apply(null, args)
        else
            fn.apply(null, args)

    get: (key, subkey, fn) =>
        if @cache[key]?[subkey]
            @_call(fn, null, @cache[key][subkey])
        else
            @_call(fn, "not found", null)


    set: (key, subkey, ttl, data, fn) =>
        @cache[key] ?= {}

        @cache[key][subkey] = data

        @_call(fn, null, null)

    clear: (key, fn) =>
        delete @cache[key]
        fn and @_call(fn, null, null)

    clear_subkey: (key, subkey, fn) =>
        delete @cache[key][subkey] if @cache[key]
        fn and @_call(fn, null, null)

    dbsize: (fn) =>
        @client.dbsize(fn)

    clear_all: (fn) =>
        @cache = {}

    close: (fn) =>
        fn and @_call(fn, null, null)

module.exports = { MemoryBackend }
