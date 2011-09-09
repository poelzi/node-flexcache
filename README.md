flexcache
=======

Flexible cache for async function calls. It is designed for preventing dirty caches more then on speed.
Different Backends allows you to cover different usecases.


# Backends


## Redis


    Best used for preventing long and slow operations on the filesysetem. Can easily be shared accross a Cluster and is
    very performant. TTL support of the Redis database scales down the memory usage. 


## Memory (soon)


    Caches are local only. Should only be used in a very narrow scope and be destoryed after every request. They are very
    fast however.


# Installation

    npm install flexcache


# Cache Identifiers


flexcache uses a two level cache, first leve is called key, second level is the hash.
By using a easy to receive key you can clear all caches depending strongly on the state of the key value. You can
also invalidate a subkey cache without touching other subkey caches.

Default behaviour:

    key is stringified first argument
    subkey is uses Flexcache.safe_hasher_all wich generates a very good but hard to determin subkey.



# Usage


Each Flexcache instance uses a backend for storage. Many Flexcache instances can share a backend, but may have
different options.

```javascript

RedisBackend = require('flexcache/backend/redis').RedisBackend
Flexcache = require('flexcache').Flexcache

backend = new RedisBackend()
fc = new Flexcache(backend, { ttl:400000 }) // 400 second timeout

slow = function(a, b, callback) { /* do something slow */ }

cached = fc.cache(slow)

```

Whatever arguments are passed to cached, they are used to compute the subkey and should therefor never hit a wrong
cache entry. 
    

Advanced Usage
--------------

```javascript

backend = new RedisBackend({port:1234})
fc = new Flexcache({
    key: function() { return arguments.1 },
    hash: function() { return "X" + arguments.0 },
    ttl: 60*1000
    });

// use a special key function for this function
rcached = fc.cache(slow, {key: function() { return arguments.2 }}); 


rcached.clear("key1")
```


## Flexcache Options

  - `hash` *function* to generate the hash or one of *'all'*, *'one'*, *'safe_one'*, *'safe_all'*. default: **safe_all**
  - `key` same as hash. default: **one**
  - `ttl` timeout in


## cache(fnc)

Creates a cache wrapper for a async function.

## cache(...).clear([key]|[args])

Clears a key and all subkeys under it. Key can be direct string or the same arguments as the function.

## cache(...).clear_subkey([key, subkey]|[args])

Clears a specific subkey under key. If key and subkey are strings, they are used directly.
You can also pass the same arguments as the normal function and let the key and subkey be calculated by the key/hash functions.






# Backends

## RedisBackend

### Notes

  - TTL is rounded to seconds.
  - TTL only works with Redis 2.1.3+


### Options

  - `host` Redis server hostname
  - `port` Redis server portno
  - `db` Database index to use
  - `pass` Password for Redis authentication
  - ...    Remaining options passed to the redis `createClient()` method.


