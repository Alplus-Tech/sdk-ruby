# frozen_string_literal: true

module Alplus
  # Holds ingest key, endpoint, environment/release tags, and safety knobs.
  # The key is read from `ALPLUS_KEY` by default and is never logged —
  # `#inspect`/`#to_s` omit it deliberately (issue #14 story 11).
  class Configuration
    DEFAULT_ENDPOINT = "https://ingest.alplus.dev"

    attr_accessor :key, :endpoint, :environment, :release, :sample_rate,
                  :enabled, :test_mode, :app_dirs, :max_queue_size,
                  :open_timeout, :read_timeout, :logger, :transport, :sleeper,
                  :before_send, :scrub_fields, :excluded_exceptions, :context_lines,
                  :breadcrumbs_enabled, :logger_breadcrumbs_enabled,
                  :post_error_log_window_ms

    # The window `Client` actually uses: the explicit setting when given,
    # otherwise 0 in test mode (synchronous delivery stays synchronous for
    # every spec that does not opt in) and 2000 ms in a real process.
    def resolved_post_error_log_window_ms
      return post_error_log_window_ms.to_i unless post_error_log_window_ms.nil?

      test_mode ? 0 : 2_000
    end

    def initialize
      @key = ENV["ALPLUS_KEY"]
      @endpoint = ENV["ALPLUS_ENDPOINT"] || DEFAULT_ENDPOINT
      @environment = ENV["ALPLUS_ENVIRONMENT"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "production"
      @release = ENV["ALPLUS_RELEASE"]
      @sample_rate = 1.0
      @enabled = true
      @test_mode = false
      @app_dirs = []
      @max_queue_size = 100
      @open_timeout = 2
      @read_timeout = 5
      @logger = nil
      @transport = nil
      # Issue (SDK parity #1): called with the wire item hash just before
      # enqueue. Return a (possibly modified) hash to send it, or `nil` to
      # drop the event entirely. A raising callback never breaks capture --
      # `Client` rescues it and sends the original item. `nil` by default
      # (no-op).
      @before_send = nil
      # Deep-walked (case-insensitive substring match) across
      # `context`/`contexts`/`tags`/`user` before `before_send` runs; a
      # matching value is replaced with `"[FILTERED]"`. See `Scrubber`.
      @scrub_fields = Scrubber::DEFAULT_SCRUB_FIELDS.dup
      # Exception class names (or an ancestor's) to never send at all --
      # e.g. `"ActionController::RoutingError"`. Empty by default: a
      # non-Rails host app gets no surprise silent drops.
      @excluded_exceptions = []
      # Lines of source before/after each in_app frame's line to attach
      # (`Stack`). `0` disables source-context capture entirely.
      @context_lines = 3
      # Auto-breadcrumbs from `ActiveSupport::Notifications` (Rails only,
      # see `Railtie`). Ignored outside Rails.
      @breadcrumbs_enabled = true
      # Log-line breadcrumbs from an attached logger (issue #47,
      # `LoggerBreadcrumbs`; the Railtie attaches `Rails.logger`).
      @logger_breadcrumbs_enabled = true
      # Post-error log window in ms (issue #47): an exception item lingers
      # this long so log lines written just after the error (Rails' own
      # exception logging included) join its breadcrumb timeline, marked
      # `after_error`. `0` disables. `nil` (the default) resolves to 0 in
      # test mode -- specs that exercise the window opt in explicitly --
      # and 2000 otherwise. `flush`/`close` seal pending items immediately.
      @post_error_log_window_ms = nil
      # Injection point for the default `Transport`'s retry backoff sleep
      # (issue #15/#16 follow-up): overridable per-`Configuration` so a
      # spec exercising `Alplus.capture_exception`/`.heartbeat` against a
      # retried response never waits on real wall-clock backoff.
      @sleeper = method(:sleep)
    end

    def valid?
      !enabled.nil? && enabled && !key.to_s.strip.empty?
    end

    def sampled?
      sample_rate >= 1.0 || rand < sample_rate
    end

    # Never expose the key. A future maintainer adding a field here must not
    # add it to this list without checking it isn't a secret.
    def inspect
      "#<Alplus::Configuration endpoint=#{endpoint.inspect} environment=#{environment.inspect} " \
        "release=#{release.inspect} enabled=#{enabled.inspect} test_mode=#{test_mode.inspect}>"
    end
    alias to_s inspect
  end
end
