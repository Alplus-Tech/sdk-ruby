# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module PostDeploy
  # Sends one envelope to `POST /e/errors` over `Net::HTTP` with an explicit
  # open/read timeout. Never raises: every transport failure (timeout,
  # connection refused, 4xx/5xx, an unparseable response) is swallowed and
  # reported as `:error`/`:rejected` so the caller (the background worker)
  # can log it without ever propagating into the host app (issue #14 story
  # 8).
  #
  # Retries a transient failure up to `Retry::MAX_ATTEMPTS` times with
  # jittered exponential backoff, honoring a 429's `Retry-After` header
  # (issue #15) — see `Retry`. Runs on
  # the existing background `Worker` thread, never the request thread.
  class Transport
    def initialize(config, sleeper: method(:sleep))
      @config = config
      @sleeper = sleeper
    end

    def send_envelope(envelope)
      body = JSON.generate(envelope)
      return :oversized if body.bytesize > Envelope::MAX_ENVELOPE_BYTES

      uri = URI.join(@config.endpoint, "/e/errors")
      result = Retry.perform(sleeper: @sleeper) { post(uri, body) }
      outcome(result)
    end

    private

    def post(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@config.key}"
      request.body = body

      http.request(request)
    end

    def outcome(result)
      case result.outcome
      when :sent then :sent
      when :permanent then :rejected
      else
        if result.error
          @config.logger&.warn("[postdeploy] transport failed: #{result.error.class}: #{result.error.message}")
          :error
        else
          :rejected
        end
      end
    end
  end

  # In-memory transport used when `config.test_mode` is true. Records every
  # envelope it would have sent instead of touching the network, so specs
  # can assert on the exact shape without a stubbed HTTP endpoint —
  # `PostDeploy.test_transport.envelopes` (issue #14 story 9).
  class TestTransport
    attr_reader :envelopes

    def initialize(*)
      @envelopes = []
    end

    def send_envelope(envelope)
      @envelopes << envelope
      :sent
    end

    def clear
      @envelopes.clear
    end
  end
end
