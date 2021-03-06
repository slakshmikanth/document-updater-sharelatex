settings = require "settings-sharelatex"
request  = require "request"
logger = require "logger-sharelatex"
RedisManager = require "./RedisManager"
crypto = require("crypto")

module.exports = TrackChangesManager =
	flushDocChanges: (doc_id, callback = (error) ->) ->
		if !settings.apis?.trackchanges?
			logger.warn doc_id: doc_id, "track changes API is not configured, so not flushing"
			return callback()

		url = "#{settings.apis.trackchanges.url}/doc/#{doc_id}/flush"
		logger.log doc_id: doc_id, url: url, "flushing doc in track changes api"
		request.post url, (error, res, body)->
			if error?
				return callback(error)
			else if res.statusCode >= 200 and res.statusCode < 300
				return callback(null)
			else
				error = new Error("track changes api returned a failure status code: #{res.statusCode}")
				return callback(error)

	FLUSH_EVERY_N_OPS: 50
	pushUncompressedHistoryOp: (doc_id, op, callback = (error) ->) ->
		RedisManager.getHistoryLoadManagerThreshold (error, threshold) ->
			return callback(error) if error?
			if TrackChangesManager.getLoadManagerBucket(doc_id) < threshold
				RedisManager.pushUncompressedHistoryOp doc_id, op, (error, length) ->
					return callback(error) if error?
					if length > 0 and length % TrackChangesManager.FLUSH_EVERY_N_OPS == 0
						# Do this in the background since it uses HTTP and so may be too
						# slow to wait for when processing a doc update.
						logger.log length: length, doc_id: doc_id, "flushing track changes api"
						TrackChangesManager.flushDocChanges doc_id,  (error) ->
							if error?
								logger.error err: error, doc_id: doc_id, "error flushing doc to track changes api"
					callback()
			else
				callback()

	getLoadManagerBucket: (doc_id) ->
		hash = crypto.createHash("md5").update(doc_id).digest("hex")
		return parseInt(hash.slice(0,4), 16) % 100
