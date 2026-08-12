# frozen_string_literal: true

require "net/http"
require "uri"
require "securerandom"

module Alplus
  # Cron/job liveness pings against Monitor's `GET|POST /h/:token`
  # (issue #16; docs/ARCHITECTURE.md §8): the token is the auth (recognized
  # → 202 even paused, unrecognized → 404); `?state=start|finish|fail`, an
  # unrecognized state falls back to `finish` (still records the run,
  # matching the Elixir SDK) rather than silently no-op-ing. Mirrors
  # `packages/sdk/src/core/heartbeat.ts`'s wire contract and reuses `Retry`
  # (issue #15) for backoff/`Retry-After` instead of duplicating it — see
  # `Retry`'s comment on why Ruby shares this where the JS SDK deliberately
  # doesn't.
  #
  # `Alplus.heartbeat` (the public entry point in `alplus.rb`) calls `ping`
  # synchronously on the caller's thread: a cron/job runner is not a web
  # request, and the caller (typically the very last statement of a job)
  # wants the ping actually sent before the process exits, not fired into
  # a background thread that may never run. This DOES block the caller
  # briefly — bounded to `HEARTBEAT_MAX_ATTEMPTS` attempts and a
  # `HEARTBEAT_MAX_RETRY_AFTER_SECONDS` cap on any 429 `Retry-After`
  # (ignoring a server-requested wait beyond that), so a slow ingest
  # endpoint can add at most ~2s, never `Transport`'s full ~30s budget.
  module Heartbeat
    VALID_STATES = %w[start finish fail].freeze
    HEARTBEAT_MAX_ATTEMPTS = 2
    HEARTBEAT_MAX_RETRY_AFTER_SECONDS = 2

    # Matches the JS SDK's `PING_ID_PATTERN` shape closely enough for a
    # server-side idempotency key; not validated against a caller-supplied
    # override here since nothing in this SDK accepts one from outside yet.
    module_function

    # Never raises: an internal error, network failure, or retryable
    # non-ok response is retried (bounded, see module doc) and then
    # swallowed, logged via `config.logger` if the retry budget is
    # exhausted. Returns `nil` always.
    #
    # The SAME `ping_id` is reused on every retry attempt within one call
    # (issue #16 defect): ingest dedups a retried ping on `ping_id`, so
    # reusing it — instead of minting a fresh id per HTTP attempt — is what
    # keeps a retried fail/finish from being processed as two separate
    # events (a duplicate incident/notification).
    def ping(token, state: "finish", config: Alplus.configuration, sleeper: method(:sleep), ping_id: nil)
      resolved_state = VALID_STATES.include?(state.to_s) ? state.to_s : "finish"
      resolved_ping_id = ping_id || generate_ping_id
      uri = build_uri(token, resolved_state, resolved_ping_id, config)

      result = Retry.perform(
        sleeper: sleeper,
        max_attempts: HEARTBEAT_MAX_ATTEMPTS,
        max_retry_after_seconds: HEARTBEAT_MAX_RETRY_AFTER_SECONDS
      ) { |_attempt| post(uri, config) }

      if result.outcome == :exhausted
        detail = result.error ? "#{result.error.class}: #{result.error.message}" : "status #{result.response&.code}"
        config.logger&.warn("[alplus] heartbeat exhausted #{HEARTBEAT_MAX_ATTEMPTS} attempt(s) (token #{token.inspect}, state #{resolved_state.inspect}): #{detail}")
      end
      nil
    rescue StandardError => e
      config.logger&.warn("[alplus] heartbeat failed internally: #{e.class}: #{e.message}")
      nil
    end

    def generate_ping_id
      SecureRandom.uuid
    end

    # Exposed for tests asserting the exact URL shape; not otherwise part
    # of the public surface.
    def build_uri(token, state, ping_id, config)
      base = config.endpoint.to_s.sub(%r{/+\z}, "")
      uri = URI.parse("#{base}/h/#{URI.encode_www_form_component(token)}")
      uri.query = URI.encode_www_form(state: state, ping_id: ping_id)
      uri
    end

    def post(uri, config)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = config.open_timeout
      http.read_timeout = config.read_timeout

      http.request(Net::HTTP::Post.new(uri.request_uri))
    end
  end
end
