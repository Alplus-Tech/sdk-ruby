# frozen_string_literal: true

module Alplus
  # Rack middleware: captures any exception that propagates up through the
  # app, then re-raises so the host's own error page / handler still runs
  # unchanged. Installed automatically by the Rails railtie; usable directly
  # in a plain Rack app (`use Alplus::RackMiddleware`).
  class RackMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue StandardError => e
      # StandardError only, deliberately: SystemExit/SignalException/
      # NoMemoryError are process-control exceptions, not app errors, and
      # must propagate untouched.
      Alplus.capture_exception(e, mechanism: "rack.middleware")
      raise
    end
  end
end
