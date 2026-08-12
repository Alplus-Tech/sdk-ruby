# frozen_string_literal: true

require_relative "alplus/version"
require_relative "alplus/id"
require_relative "alplus/configuration"
require_relative "alplus/stack"
require_relative "alplus/envelope"
require_relative "alplus/transport"
require_relative "alplus/worker"
require_relative "alplus/client"
require_relative "alplus/rack_middleware"

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

    # The active transport (real `Transport` or, under `config.test_mode`,
    # `TestTransport`). `Alplus.test_transport.envelopes` gives specs direct
    # access to every envelope captured so far.
    def test_transport
      client.transport
    end

    # Test-only: drops the memoized client/configuration so the next access
    # rebuilds them. Not needed in production code.
    def reset!
      CLIENT_MUTEX.synchronize { @client = nil }
      @configuration = nil
    end
  end
end

require_relative "alplus/railtie" if defined?(::Rails::Railtie)
