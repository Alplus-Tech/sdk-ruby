# frozen_string_literal: true

require_relative "rails_error_subscriber"
require_relative "notifications_subscriber"

module Alplus
  # Installs `Alplus::RackMiddleware` and auto-detects the app root from
  # Rails config, so a Rails app gets automatic unhandled-exception capture
  # with zero explicit wiring beyond setting the ingest key (issue #14
  # story 2/12).
  #
  # Middleware position matters, and there are TWO exception renderers to
  # get inside of, not one:
  #
  #   * `ActionDispatch::ShowExceptions` (outer) renders the public error
  #     page in production.
  #   * `ActionDispatch::DebugExceptions` (inner, closer to the app) renders
  #     the developer error page in development — and, crucially, it does
  #     NOT re-raise. In development it rescues the exception and returns the
  #     debug page, so any middleware OUTSIDE it never sees the exception.
  #
  # Inserting after `ShowExceptions` (the original fix) works in production
  # — there `DebugExceptions` re-raises and our middleware, sitting between
  # the two, catches the re-raised exception. But in DEVELOPMENT
  # `DebugExceptions` swallows first, so unhandled web errors were lost
  # (verified against a real Rails 8 app, 2026-08-17).
  #
  # `insert_after ActionDispatch::DebugExceptions` places `RackMiddleware`
  # inside BOTH renderers — the innermost exception boundary, matching
  # `Sentry::Rails::CaptureExceptions`. The app's exception now reaches our
  # `rescue`/re-raise before either renderer runs, in every environment.
  class Railtie < ::Rails::Railtie
    initializer "alplus.configure" do |app|
      config = Alplus.configuration
      config.app_dirs = [::Rails.root.to_s] if config.app_dirs.empty? && ::Rails.respond_to?(:root) && ::Rails.root

      if defined?(::ActionDispatch::DebugExceptions) && app.middleware.respond_to?(:insert_after)
        app.middleware.insert_after ::ActionDispatch::DebugExceptions, Alplus::RackMiddleware
      else
        app.middleware.insert 0, Alplus::RackMiddleware
      end

      if ::Rails.respond_to?(:error) && ::Rails.error.respond_to?(:subscribe)
        ::Rails.error.subscribe(Alplus::RailsErrorSubscriber.new)
      end

      Alplus::NotificationsSubscriber.install!

      # Install the optional job integrations HERE, not at gem-require time
      # in `alplus.rb`. By the time this initializer runs, Bundler has
      # loaded every gem and Rails has booted its frameworks, so require
      # order no longer matters. In a real Rails app `ActiveJob::Base`
      # autoloads only after boot, so the `defined?` check in `alplus.rb`
      # is false when the gem loads and would silently skip the install.
      #
      # `install!` is idempotent, so overlapping with `alplus.rb`'s
      # non-Rails fallback path is safe.
      if defined?(::Sidekiq)
        require_relative "sidekiq"
        Alplus::Sidekiq.install!
      end

      if defined?(::ActiveSupport) && ::ActiveSupport.respond_to?(:on_load)
        # Fires whenever `ActiveJob::Base` loads, regardless of gem require
        # order relative to `alplus`.
        ::ActiveSupport.on_load(:active_job) do
          require_relative "active_job"
          Alplus::ActiveJob.install!
        end
      end
    end
  end
end
