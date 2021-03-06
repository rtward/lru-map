# LRUMap

Wraps ES6 Map (a key-value structure) in an LRU eviction framework complete with "max age" checking.

Branch  | Build Status | Coverage
------- | ------------ | --------
master  | [![master Build Status](https://travis-ci.org/bchociej/lru-map.svg?branch=master)](https://travis-ci.org/bchociej/lru-map) | [![master Coverage Status](https://coveralls.io/repos/bchociej/lru-map/badge.svg?branch=master&service=github)](https://coveralls.io/github/bchociej/lru-map?branch=master)
develop | [![develop Build Status](https://travis-ci.org/bchociej/lru-map.svg?branch=develop)](https://travis-ci.org/bchociej/lru-map) | [![develop Coverage Status](https://coveralls.io/repos/bchociej/lru-map/badge.svg?branch=develop&service=github)](https://coveralls.io/github/bchociej/lru-map?branch=develop)

## Usage

Use npm to install (or depend on) `lru-map`. Suggested way to add LRUMap to your code:

```
var LRUMap = require('lru-map');
```


## Terminology

* **LRU**: Least Recently Used
* **stale**: older than the max age threshold; the opposite is **fresh**
* **evict**: to delete an entry because it is the Least Recently Used entry and no longer fits in the collection


## API

### new LRUMap([options])

Construct a new LRUMap with the specified `options` (an object):

* `maxSize`: the maximum size that the LRUMap can grow to before evicting entries; default `Infinity`
* `maxAge`: the maximum age, in seconds, that an entry can be before being reaped as stale; default `Infinity`
* `calcSize`: a `function(value)` that returns the integer size of the value, however you like to define it; the default behavior is that each entry has a size of 1
* `onEvict`: a callback `function(key, value)` that is called when an entry is evicted vis-a-vis LRU policy
* `onStale`: a callback `function(key, value)` that is called when an entry is removed as stale (too old)
* `onRemove`: a callback that occurs when either `onEvict` or `onStale` is called; same signature
* `accessUpdatesTimestamp`: true/false; do you want the act of accessing an entry to update its timestamp for `maxAge` staleness calculations? If not, the entry will age out based on when it was last `set()` (inserted) into the LRUMap. Default `false`.
* `warmer`: a callback `function(lrumap)` that is called to pre-populate the cache.  The function will not be called initially.  See the warm function for more details.

Note that even if you take great care to write a `calcSize` function that computes a byte size for entries, each entry still carries some overhead in the LRUMap implementation.


### #warm()

Calles the warmer function, and waits for it to finish. Returns a promise which will be resolved when the warmer is done.  If the warmer function returns a promise, that will be waited on as well.


### #maxAge([age])

If `age`, a positive number of seconds, is specified, set the `maxAge` option to that value. Otherwise, return the current setting. When mutating the value, the effect is immediate--stale entries are evicted.


### #accessUpdatesTimestamp([boolean])

If the boolean argument is specified, set the `accessUpdatesTimestamp` option to that value. Otherwise, return the current setting.


### #maxSize([size])

If `size`, a positive number, is specified, set the `maxSize` option to that value. Otherwise, return the current setting. When mutating the value, the effect is immediate--LRU entries are evicted until the setting is satisfied. Stale entries older than `maxAge` are reaped before checking size, so that the fewest possible non-stale entries are evicted.


### #currentSize()

Return the current sum total of entry sizes present in the LRUMap. Does not cause eviction or `maxAge` checking, so this method is idempotent and constant-time. If desired, you can call `#reapStale()` before calling this method.


### #fits(value)

Check if the specified `value` would fit in the LRUMap, based on the `calcSize` function. Does not cause eviction or `maxAge` checking, so this method is idempotent and constant-time. If desired, you can call `#reapStale()` before calling this method.


### #wouldCauseEviction(value)

Check if the specified `value` would result in existing entries being evicted from the LRUMap vis-a-vis LRU policy. Does not cause eviction or `maxAge` checking, so this method is idempotent and constant-time. If desired, you can call `#reapStale()` before calling this method.


### #onEvict([callback])

Set the `onEvict` callback to the specified one.


### #onStale([callback])

Set the `onStale` callback to the specified one.


### #onRemove([callback])

Set the `onRemove` callback to the specified one.


### #reapStale()

Remove entries older than the `maxAge`. If the `maxAge` is `Infinity`, this method does nothing.

If `accessUpdatesTimestamp` is `true`, stale-reaping is inherently done in LRU order and is therefore more efficient (requires exactly as many iterations as the number of stale entries). If not, this method runs in linear time.


### #set(key, value)

Insert or update the specified `<key, value>` pair into the map, evicting LRU entries and/or reaping entries older than the `maxAge`, if necessary. `key` and `value` can both be of any type. If the `value` is larger than `maxSize` according to `calcSize`, an Error will be thrown.

This method affects the LRU order and staleness timestamp for the entry.

This method runs as efficiently as the underlying `Map#set()` implementation.


### #setIfNull(key, promisedValue, [opts = {}])

Atomically check if the `key` exists, returning it if so, and updating with the resolved `promiseValue` if not. Times out in `opts.timeout` milliseconds, which must be a positive number, can be `Infinity`, and defaults to `10000`.

Simultaenous calls to `setIfNull()` with the same `key` will receive a promise for the pending update, which corresponds to the first caller's `promisedValue`. (If the corresponding `promisedValue` is not a promise, i.e. if the entry is synchronously updated, later calls will always receive an immediately resolved promise, as long as the entry is not evicted or stale.)

If `promisedValue` is a function, it will be evaluated before use unless `opts.invokeNewValueFunction` is `false`.

This method affects the LRU order and staleness timestamp for the entry.

This method runs as efficiently as a `LRUMap#get()` call; if the `key` does not exist, the additional complexity of resolving the `promisedValue` is incurred, as well as the complexity of a call to `LRUMap#set()`


### #delete(key)

Remove the specified `key` (and its associated value) from the map. Because `#delete()` only reduces the size of the map, no eviction can occur. Stale entries are reaped, however. If the key existed in the map when this method was called, it will return `true`; otherwise, it will return `false`.

This method runs as efficiently as the underlying `Map#delete()` implementation plus an additional invocation of `#reapStale()`.


### #clear()

Remove all entries from the map. Runs as efficiently as the underlying `Map#clear()` implementation.


### #get(key)

Retrieve the value associated with the specified `key`. Does not cause eviction or staleness-checking, but updates LRU order and, if `accessUpdatesTimestamp` is true, modifies the entry's staleness timestamp.


### #has(key)

Returns `true` or `false` to indicate whether the map contains the specified `key`. Stales are reaped before checking for the `key`. Eviction and LRU order are not affected.

This method runs as efficiently as the underlying `Map#has()` implementation plus an preceding invocation of `#reapStale()`.


### #peek(key)

Retrieve the value associated with the specified `key` without affecting LRU order or staleness timestamp. Stale-reaping does occur prior to retrieving the requested entry.

This method runs as efficiently as the underlying `Map#get()` implementation plus an preceding invocation of `#reapStale()`.


### #sizeOf(key)

Retrieves the _stored_ size of the value associated with the specified `key`. `calcSize` is **not** called again for this operation. No effect on LRU order or staleness timestamps. Does not cause eviction or stale-reaping. Idempotent. As efficient as the underlying `Map#get()` implementation.


### #keys()

Reaps stales and then returns an iterator to the keys in the map.


### #values()

Reaps stales and then returns an iterator to the values in the map. When the iterator's `next()` function accesses a value, that value's timestamp is updated, as long as `accessUpdatesTimestamp` is `true`.


### #entries()

Reaps stales and then returns an iterator to the map entries in Array form like `[key, value]`. When the iterator's `next()` function access a value, that value's staleness timestamp is updated, as long as `accessUpdatesTimestamp` is `true`.


### #forEach(callback[, thisArg])

Reaps stales and then calls the callback for each entry in the map in order. The callback signature is `function(value, key, map)`. If `thisArg` is specified, the callback invocation is bound with `thisArg` as `this` for each invocation. If `accessUpdatesTimestamp` is `true`.


## Legal

Copyright 2015 Ben Chociej

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this package except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
