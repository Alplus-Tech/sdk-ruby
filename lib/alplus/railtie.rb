# frozen_string_literal: true

require_relative "rails_error_subscriber"

module Alplus
  # Installs `Alplus::RackMiddleware` and auto-detects the app root from
  # Rails config, so a Rails app gets automatic unhandled-exception capture
  # with zero explicit wiring beyond setting the ingest key (issue #14
  # story 2/12).
  #
  # Middleware position matters: `ActionDispatch::ShowExceptions` rescues
  # every exception raised by the app (and by middleware closer to the app)
  # and renders an error page instead of re-raising. A middleware inserted
  # OUTSIDE it (`insert 0`, the original bug) never sees the exception —
  # `ShowExceptions` has already swallowed it. `insert_after
  # ActionDispatch::ShowExceptions` places `RackMiddleware` BETWEEN
  # `ShowExceptions` and the app, so the exception passes through our
  # `rescue`/re-raise before `ShowExceptions` gets a chance to rescue it.
  class Railtie < ::Rails::Railtie
    initializer "alplus.configure" do |app|
      config = Alplus.configuration
      config.app_dirs = [::Rails.root.to_s] if config.app_dirs.empty? && ::Rails.respond_to?(:root) && ::Rails.root

      if defined?(::ActionDispatch::ShowExceptions) && app.middleware.respond_to?(:insert_after)
        app.middleware.insert_after ::ActionDispatch::ShowExceptions, Alplus::RackMiddleware
      else
        app.middleware.insert 0, Alplus::RackMiddleware
      end

      if ::Rails.respond_to?(:error) && ::Rails.error.respond_to?(:subscribe)
        ::Rails.error.subscribe(Alplus::RailsErrorSubscriber.new)
      end
    end
  end
end
