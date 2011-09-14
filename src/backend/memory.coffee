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


    set: (key, subkey, data, options, fn) =>
        @cache[key] ?= {}

        @cache[key][subkey] = data

        @_call(fn, null, null)

    clear_group: (group, fn) =>
        delete @cache[group]
        fn and @_call(fn, null, null)

    clear_hash: (group, hash, fn) =>
        delete @cache[group][hash] if @cache[group]
        fn and @_call(fn, null, null)

    clear_all: (fn) =>
        @cache = {}

    dbsize: (fn) =>
        @_call(fn, null, 0)

    close: (fn) =>
        fn and @_call(fn, null, null)

module.exports = { MemoryBackend }
