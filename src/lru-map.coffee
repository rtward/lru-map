Map = require 'es6-map'
Symbol = require 'es6-symbol'
Promise = require 'bluebird'

module.exports = class LRUMap
	constructor: (opts = {}) ->
		this._maxSize = opts.maxSize ? (Infinity)
		this._maxAge = opts.maxAge ? (Infinity)
		this.calcSize = opts.calcSize ? ((value) -> 1)
		this.user_onEvict = opts.onEvict ? ((key, value) -> undefined)
		this.user_onStale = opts.onStale ? ((key, value) -> undefined)
		this._onRemove = opts.onRemove ? ((key, value) -> undefined)
		this._accessUpdatesTimestamp = opts.accessUpdatesTimestamp ? false
		this.warmer = opts.warmer ? (cache, args...) -> Promise.resolve()

		this.warmed = undefined

		unless typeof this._maxSize is 'number' and this._maxSize >= 0
			throw new Error 'maxSize must be a non-negative number'

		unless typeof this.calcSize is 'function'
			throw new TypeError 'calcSize must be a function'

		unless typeof this.user_onEvict is 'function'
			throw new TypeError 'onEvict must be a function'

		unless typeof this.user_onStale is 'function'
			throw new TypeError 'onStale must be a function'

		unless typeof this._onRemove is 'function'
			throw new TypeError 'onRemove must be a function'

		unless typeof this.warmer is 'function'
			throw new TypeError 'warmer must be a function'

		this._onEvict = (key, value) ->
			this._onRemove(key, value)
			this.user_onEvict(key, value)

		this._onStale = (key, value) ->
			this._onRemove(key, value)
			this.user_onStale(key, value)

		this.atomicInflights = new Map
		this.map = new Map
		this.total = 0

		this[Symbol.iterator] = -> @entries()

		if LRUMap.__testing__ is true
			@testMap = this.map
			@testInflights = this.atomicInflights
			@testSetTotal = (x) -> this.total = x
			@testSetMaxAge = (x) -> this._maxAge = x

	# immediate effect; reaps stales
	maxAge: (age) ->
		if age?
			unless typeof age is 'number' and age > 0
				throw new Error 'age must be a positive number of seconds'

			this._maxAge = age

			@reapStale()

		return this._maxAge

	# no immediate effect
	accessUpdatesTimestamp: (doesIt) ->
		if doesIt?
			unless typeof doesIt is 'boolean'
				throw new TypeError 'accessUpdatesTimestamp accepts a boolean'

			this._accessUpdatesTimestamp = doesIt

		return this._accessUpdatesTimestamp

	# immediate effect; reaps stales
	maxSize: (size) ->
		if size?
			unless typeof size is 'number' and size > 0
				throw new Error 'size must be a positive number'

			this._maxSize = size

			@reapStale()

			entries = this.map.entries()
			while this.total > this._maxSize
				oldest = entries.next().value

				break unless oldest?

				this.map.delete oldest[0]
				this.total -= oldest[1].size

				this._onEvict oldest[0], oldest[1].value

		return this._maxSize

	# returns a promise that will be fulfilled when the cache is done warming
	warm: (args...) ->
		unless this.warmed? then this.warmed = Promise.resolve(this.warmer(this, args...))
		return this.warmed

	# non-mutating; idempotent
	currentSize: ->
		return this.total

	# non-mutating; idempotent
	fits: (value) ->
		return this.calcSize(value) <= this._maxSize

	# non-mutating; idempotent
	wouldCauseEviction: (value) ->
		return (this.calcSize(value) + this.total > this._maxSize) and (this.total > 0)

	# non-mutating configuration method; no immediate effect
	onEvict: (fn) ->
		unless typeof fn is 'function'
			throw new TypeError 'argument to onEvict must be a function'

		this._onEvict = fn

	# non-mutating configuration method; no immediate effect
	onStale: (fn) ->
		unless typeof fn is 'function'
			throw new TypeError 'argument to onStale must be a function'

		this._onStale = fn

	# non-mutating configuration method; no immediate effect
	onRemove: (fn) ->
		unless typeof fn is 'function'
			throw new TypeError 'argument to onRemove must be a function'

		this._onRemove = fn

	# reaps stales
	reapStale: ->
		return if this._maxAge is Infinity

		entries = this.map.entries()
		cur = entries.next().value

		while cur?
			diff = (+(new Date) - cur[1].timestamp) / 1000

			if diff > this._maxAge
				this.map.delete cur[0]
				this.total -= cur[1].size

				this._onStale cur[0], cur[1].value
			else
				if this._accessUpdatesTimestamp
					break

			cur = entries.next().value

	# mutates Map state; affects LRU eviction; affects staleness; reaps stales
	set: (key, value) ->
		@reapStale()

		size = this.calcSize value
		timestamp = +(new Date)
		priorTotal = this.total

		if isNaN(size) or size < 0 or typeof size isnt 'number'
			throw new Error 'calcSize() must return a positive number'

		if this.map.has key
			priorTotal -= @sizeOf key

		if size > this._maxSize
			throw new Error "cannot store an object of that size (maxSize = #{this._maxSize}; value size = #{size})"

		entries = this.map.entries()

		while priorTotal + size > this._maxSize
			oldest = entries.next().value

			break unless oldest?

			this.map.delete oldest[0]
			priorTotal -= oldest[1].size

			this._onEvict oldest[0], oldest[1].value

		this.map.set key, {size, value, timestamp}
		this.total = priorTotal + size

		return this

	# mutates Map state; affects LRU eviction; affects staleness; reaps stales
	setIfNull: (key, newValue, opts = {}) ->
		unless typeof opts is 'object'
			throw new TypeError 'opts must be an object'

		opts.timeout ?= 10000
		opts.invokeNewValueFunction ?= true
		opts.onCacheHit ?= -> undefined
		opts.onCacheMiss ?= -> undefined

		unless typeof opts.timeout is 'number' and opts.timeout >= 1
			throw new TypeError 'opts.timeout must be a positive number (possibly Infinity)'

		unless typeof opts.invokeNewValueFunction is 'boolean'
			throw new TypeError 'opts.invokeNewValueFunction must be boolean'

		unless typeof opts.onCacheHit is 'function'
			throw new TypeError 'opts.onCacheHit must be a function'

		unless typeof opts.onCacheMiss is 'function'
			throw new TypeError 'opts.onCacheMiss must be a function'

		if this.atomicInflights.has key
			setTimeout -> opts.onCacheHit key
			return this.atomicInflights.get key

		@reapStale()

		if this.map.has key
			setTimeout -> opts.onCacheHit key
			return Promise.resolve @get key

		setTimeout -> opts.onCacheMiss key

		if opts.invokeNewValueFunction and typeof newValue is 'function'
			newValue = newValue()

		inflight = Promise.resolve(newValue)
			.timeout(opts.timeout)
			.tap (value) =>
				this.atomicInflights.delete key
				@reapStale()
				@set key, value
			.catch (e) =>
				this.atomicInflights.delete key
				Promise.reject e

		this.atomicInflights.set key, inflight
		return inflight

	# mutates Map state; affects LRU eviction; affects staleness; reaps stales
	delete: (key) ->
		if this.map.has key
			this.total -= @sizeOf key
			this.map.delete key
			@reapStale()
			return true
		else
			@reapStale()
			return false

	# mutates Map state
	clear: ->
		this.map.clear()
		this.total = 0
		return

	# affects LRU eviction; affects staleness if accessUpdatesTimestamp
	get: (key) ->
		entry = this.map.get key

		return undefined unless entry?

		this.map.delete key

		if this._accessUpdatesTimestamp
			entry.timestamp = +(new Date)

		this.map.set key, entry

		return entry.value

	# non-evicting; reaps stales
	has: (key) ->
		@reapStale()
		return this.map.has key

	# non-evicting; reaps stales
	peek: (key) ->
		@reapStale()
		entry = this.map.get key
		return entry?.value

	# non-mutating; idempotent
	sizeOf: (key) ->
		entry = this.map.get key
		return entry?.size

	# non-mutating; idempotent
	ageOf: (key) ->
		entry = this.map.get key

		if entry?
			return Math.round((+(new Date) - entry.timestamp) / 1000)

	# non-mutating; idempotent
	isStale: (key) ->
		entry = this.map.get key

		if entry?
			return @ageOf(key) > this._maxAge

	# non-evicting; reaps stales
	keys: ->
		@reapStale()
		return this.map.keys()

	# non-evicting; reaps stales
	values: ->
		@reapStale()
		iter = this.map.values()

		return {
			next: =>
				ev = iter.next().value

				if ev?
					if this._accessUpdatesTimestamp
						ev.timestamp = +(new Date)

					return {value: ev.value, done: false}

				return {done: true}
		}

	# non-evicting; reaps stales
	entries: ->
		@reapStale()
		iter = this.map.entries()

		return {
			next: =>
				entry = iter.next().value

				if entry?
					if this._accessUpdatesTimestamp
						entry[1].timestamp = +(new Date)

					return {done: false, value: [entry[0], entry[1].value]}
				else
					return {done: true}
		}

	# non-evicting; reaps stales
	forEach: (callback, thisArg) ->
		@reapStale()
		this.map.forEach (value, key, map) =>
			if this._accessUpdatesTimestamp
				value.timestamp = +(new Date)

			callback.call thisArg, value.value, key, this

		return
