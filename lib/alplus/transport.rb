# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Alplus
  # Sends one envelope to `POST /e/errors` over `Net::HTTP` with an explicit
  # open/read timeout. Never raises: every transport failure (timeout,
  # connection refused, 4xx/5xx, an unparseable response) is swallowed and
  # reported as `:error` so the caller (the background worker) can log it
  # without ever propagating into the host app (issue #14 story 8).
  class Transport
    def initialize(config)
      @config = config
    end

    def send_envelope(envelope)
      body = JSON.generate(envelope)
      return :oversized if body.bytesize > Envelope::MAX_ENVELOPE_BYTES

      uri = URI.join(@config.endpoint, "/e/errors")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@config.key}"
      request.body = body

      response = http.request(request)
      response.is_a?(Net::HTTPSuccess) ? :sent : :rejected
    rescue StandardError => e
      @config.logger&.warn("[alplus] transport failed: #{e.class}: #{e.message}")
      :error
    end
  end

  # In-memory transport used when `config.test_mode` is true. Records every
  # envelope it would have sent instead of touching the network, so specs
  # can assert on the exact shape without a stubbed HTTP endpoint —
  # `Alplus.test_transport.envelopes` (issue #14 story 9).
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
