# frozen_string_literal: true

module Alplus
  # Rack middleware: captures any exception that propagates up through the
  # app, then re-raises so the host's own error page / handler still runs
  # unchanged. Installed automatically by the Rails railtie; usable directly
  # in a plain Rack app (`use Alplus::RackMiddleware`).
  #
  # Also resets `Scope` to a fresh, empty one for the duration of the
  # request (issue #17): a thread-pool server (Puma, Passenger) reuses OS
  # threads across requests, so without this a `set_user`/`set_tag` call in
  # request A would otherwise still be visible to request B if it happens
  # to land on the same thread.
  #
  # Session lifecycle (issue #12): opens a fresh request-scoped `Session`
  # (`Session.with_clean_session`, the same reused-thread guard as `Scope`
  # above) and closes it (`Alplus.close_session`) once `@app.call` returns
  # OR raises. Unlike `sdks/elixir/lib/alplus_sdk/plug.ex` (which cannot
  # rescue a downstream plug's exception — see that module's moduledoc),
  # Rack middleware genuinely wraps the rest of the stack in one method
  # call, so `rescue`/`ensure` here is the complete, reliable crash signal:
  # no separate telemetry hook is needed.
  class RackMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      Scope.with_clean_scope { Session.with_clean_session { call_app(env) } }
    end

    private

    def call_app(env)
      @app.call(env)
    rescue StandardError => e
      # StandardError only, deliberately: SystemExit/SignalException/
      # NoMemoryError are process-control exceptions, not app errors, and
      # must propagate untouched. `mark_crashed` runs BEFORE
      # `capture_exception` below: that call would otherwise mark the
      # session merely `:errored` (any `"error"`-level capture does), and
      # `:crashed` must win regardless of call order — `Session`'s
      # severity ordering makes this safe either way.
      Session.current&.mark_crashed
      Alplus.capture_exception(e, mechanism: "rack.middleware")
      raise
    ensure
      Alplus.close_session
    end
  end
end
