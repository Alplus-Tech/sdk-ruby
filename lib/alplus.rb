# frozen_string_literal: true

require_relative "alplus/version"
require_relative "alplus/id"
require_relative "alplus/scrubber"
require_relative "alplus/configuration"
require_relative "alplus/stack"
require_relative "alplus/envelope"
require_relative "alplus/retry"
require_relative "alplus/transport"
require_relative "alplus/worker"
require_relative "alplus/dedup"
require_relative "alplus/scope"
require_relative "alplus/session"
require_relative "alplus/pending_window"
require_relative "alplus/client"
require_relative "alplus/logger_breadcrumbs"
require_relative "alplus/rack_middleware"
require_relative "alplus/heartbeat"

# Error reporting for `POST /e/errors` on AL+ Observe. Mirrors the wire
# contract of `@alplus/sdk` (TypeScript) and the Elixir SDK (see
# docs/ARCHITECTURE.md §8, docs/BUILD.md §5).
#
#   Alplus.configure do |config|
#     config.key = ENV["ALPLUS_KEY"]      # alp_... ingest key, `ingest` scope
#     config.environment = "production"
#     config.release = "v1.2.3"
#   end
#
#   Alplus.capture_exception(exception)
#   Alplus.capture_message("something happened", level: "warning")
#
# Never raises into the host app: every public method here swallows its own
# internal errors and always returns the generated `err_` event id.
module Alplus
  # Guards the `@client`/`@configuration` singleton memoization below.
  # Module-level (not lazily built) so there is no first-access race on the
  # mutex itself.
  CLIENT_MUTEX = Mutex.new
  private_constant :CLIENT_MUTEX

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      CLIENT_MUTEX.synchronize { @client = nil }
      configuration
    end

    # Memoized under a mutex: two threads racing the very first capture
    # call must not each construct a `Client` (and, with it, a second
    # background `Worker` thread).
    def client
      return @client if @client

      CLIENT_MUTEX.synchronize { @client ||= Client.new(configuration) }
    end

    # The memoized client if one exists, without constructing it. The
    # log-breadcrumb hook (issue #47) uses this: a boot-time log line must
    # not force client construction before the host finishes configuring.
    def initialized_client
      @client
    end

    def capture_exception(exception, **options)
      client.capture_exception(exception, **options)
    rescue StandardError
      Id.generate_event_id
    end

    def capture_message(message, **options)
      client.capture_message(message, **options)
    rescue StandardError
      Id.generate_event_id
    end

    # Blocks up to `timeout` seconds for the background queue to drain.
    # Mainly useful in tests and at the end of a short-lived script.
    def flush(timeout: 2)
      client.flush(timeout: timeout)
    rescue StandardError
      false
    end

    # Pings AL+ Monitor's `GET|POST /h/:token` for cron/job liveness
    # (issue #16): `state:` is `"start"`, `"finish"` (the default), or
    # `"fail"`. Reuses the same retry/backoff as event delivery (`Retry`).
    # Fail-safe: never raises into the caller, always returns `nil`.
    def heartbeat(token, state: "finish")
      Heartbeat.ping(token, state: state, config: configuration)
      nil
    rescue StandardError
      nil
    end

    # Request-scoped scope ergonomics (issue #17): set once (typically at
    # the top of a request, e.g. in a `before_action`) and applied to every
    # `capture_exception`/`capture_message` call for the rest of the
    # current thread/request. See `Scope`. Every setter is fail-safe.
    def set_user(user)
      Scope.current.set_user(user)
      nil
    rescue StandardError
      nil
    end

    def set_tag(key, value)
      Scope.current.set_tag(key, value)
      nil
    rescue StandardError
      nil
    end

    def set_context(name, data)
      Scope.current.set_context(name, data)
      nil
    rescue StandardError
      nil
    end

    def add_breadcrumb(message: nil, category: nil, level: nil, data: nil, ts: nil)
      Scope.current.add_breadcrumb(message: message, category: category, level: level, data: data, ts: ts)
      nil
    rescue StandardError
      nil
    end

    # Closes the current thread's request-scoped `Session` (issue #12), if
    # one is active (see `RackMiddleware`): reports it to
    # `POST /e/sessions` via `Client#report_session`. A no-op if no session
    # is active. Fail-safe: never raises. Not typically called directly —
    # `RackMiddleware` calls this once `@app.call` returns or raises.
    def close_session
      session = Session.current
      return nil unless session

      client.report_session(session)
      nil
    rescue StandardError
      nil
    end

    # :nodoc: host tests use `Alplus::Testing`.
    def test_transport
      client.transport
    end

    # :nodoc: host tests use `Alplus::Testing.reset!`.
    def reset!
      CLIENT_MUTEX.synchronize { @client = nil }
      @configuration = nil
      Dedup.reset!
    end
  end
end

require_relative "alplus/testing"
require_relative "alplus/railtie" if defined?(::Rails::Railtie)

# Optional integrations (issue: SDK parity #4/#5): only loaded/activated
# when the host app already loaded the corresponding library. Neither gem
# is ever `require`d by this file, and this SDK never declares either as a
# runtime dependency -- see `lib/alplus/sidekiq.rb`/`lib/alplus/active_job.rb`.
#
# This top-level block is the NON-RAILS fallback (or the case where the
# host requires `sidekiq`/`active_job` before `alplus`). Under Rails,
# `ActiveJob::Base` autoloads only after boot, so these `defined?` checks
# are false when the gem loads; the Railtie re-runs the install after boot
# with correct timing (see `railtie.rb`). `install!` is idempotent, so the
# two paths never double-install.
if defined?(::Sidekiq)
  require_relative "alplus/sidekiq"
  Alplus::Sidekiq.install!
end

if defined?(::ActiveJob::Base)
  require_relative "alplus/active_job"
  Alplus::ActiveJob.install!
end
