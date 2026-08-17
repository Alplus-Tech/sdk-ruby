# frozen_string_literal: true

require "active_support/concern"

module Alplus
  # Optional ActiveJob integration. Namespaced under `Alplus::ActiveJob`
  # (not top-level) so it never collides with `::ActiveJob`. Safe to load
  # unconditionally -- `alplus.rb` only `require_relative`s this file when
  # `defined?(::ActiveJob::Base)` is already true, and `install!` re-checks
  # that guard, so a host app that never loads ActiveJob never activates
  # any of this. This gem's runtime dependency list stays empty either
  # way: `active_support/concern` is part of ActiveJob's own dependency
  # tree, never `require`d unless ActiveJob already pulled it in.
  module ActiveJob
    # Mixed into `::ActiveJob::Base` by `install!`. Wraps every job's
    # `perform` in an `around_perform` hook: captures the exception with
    # job context (class, queue, scrubbed arguments), then RE-RAISES so
    # ActiveJob's own retry/discard handling (`retry_on`/`discard_on`)
    # still runs unchanged -- this is an observer, not an error handler
    # that swallows failures.
    module ErrorReporting
      extend ActiveSupport::Concern

      included do
        around_perform :alplus_capture_around_perform
      end

      private

      def alplus_capture_around_perform
        yield
      rescue Exception => e # rubocop:disable Lint/RescueException
        alplus_capture_job_exception(e)
        raise
      end

      def alplus_capture_job_exception(exception)
        Alplus.capture_exception(
          exception,
          mechanism: "active_job",
          contexts: { job: alplus_job_context }
        )
      rescue StandardError
        nil
      end

      def alplus_job_context
        scrub_fields = Alplus.configuration.scrub_fields.map { |f| f.to_s.downcase }
        {
          class: self.class.name,
          queue: (respond_to?(:queue_name) ? queue_name : nil),
          job_id: (respond_to?(:job_id) ? job_id : nil),
          arguments: Alplus::Scrubber.deep_scrub(arguments, scrub_fields)
        }.compact
      end
    end

    class << self
      # Idempotent: mixing `ErrorReporting` into `::ActiveJob::Base` more
      # than once is a no-op (Ruby's own `Module#include` is already
      # idempotent for the same module, but `@installed` also skips the
      # guard checks/log-free re-run cheaply).
      def install!
        return if @installed
        return unless defined?(::ActiveJob::Base)

        ::ActiveJob::Base.include(ErrorReporting)
        @installed = true
      end

      # Test-only: lets a spec re-drive `install!`. Not called by
      # production code.
      def reset!
        @installed = false
      end
    end
  end
end
