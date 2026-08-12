# frozen_string_literal: true

require "spec_helper"
require "rails"
require "action_controller/railtie"
require "rack/test"
require "logger"

# Force-load the railtie now that `::Rails::Railtie` exists. `lib/alplus.rb`
# only requires it conditionally at `alplus.rb` load time (spec_helper.rb
# requires "alplus" before this file requires "rails"), matching how a real
# host app's Gemfile order determines it — see railtie.rb's own comment.
require_relative "../../lib/alplus/railtie"

RSpec.describe "Alplus Rails auto-capture", :aggregate_failures do
  include Rack::Test::Methods

  # A `Rails::Application` can only be initialized once per process
  # (`initialize!` is not idempotent), so the whole app + routes + a
  # controller that raises are built exactly once here and reused by every
  # example in this file via Rack::Test against the REAL middleware stack
  # (`ActionDispatch::ShowExceptions` included) — the only way to actually
  # prove `Alplus::RackMiddleware`'s position, not just its class in
  # isolation.
  before(:all) do
    unless defined?(RailtieSpecController)
      Object.const_set(:RailtieSpecController, Class.new(ActionController::Base) do
        def boom
          raise "boom from the controller"
        end

        def ok
          render plain: "ok"
        end
      end)

      app_class = Class.new(Rails::Application) do
        config.eager_load = false
        config.secret_key_base = "railtie_spec_test_secret_key_base_0123456789"
        config.hosts.clear
        config.logger = Logger.new(IO::NULL)
        config.action_dispatch.show_exceptions = :all
        config.consider_all_requests_local = false

        routes.append do
          get "/boom", to: "railtie_spec#boom"
          get "/ok", to: "railtie_spec#ok"
        end
      end
      app_class.initialize!
    end

    # spec_helper.rb's global `before(:each)` hook calls `Alplus.reset!`
    # (needed so every OTHER spec file starts from a clean configuration),
    # which would also wipe the `app_dirs` the railtie sets here — capture
    # it once, at boot, the same way a real Rails app's initializer runs
    # exactly once and is never re-applied per request.
    @railtie_detected_app_dirs = Alplus.configuration.app_dirs.dup
  end

  def app
    Rails.application
  end

  before do
    # `Alplus.configure` only clears the memoized client (giving each
    # example a fresh `TestTransport`/empty `envelopes`) — NOT the full
    # `Alplus.reset!`, which would also wipe `config.app_dirs`, the one
    # thing the railtie's `initializer` sets exactly once at app boot
    # (`before(:all)` above), same as a real Rails app never re-runs its
    # initializers per request.
    Alplus.configure do |c|
      c.key = "alp_p_test_key"
      c.test_mode = true
    end
  end

  it "installs Alplus::RackMiddleware inside ActionDispatch::ShowExceptions" do
    stack = Rails.application.middleware.map(&:klass)
    show_exceptions_index = stack.index(ActionDispatch::ShowExceptions)
    alplus_index = stack.index(Alplus::RackMiddleware)

    expect(show_exceptions_index).not_to be_nil
    expect(alplus_index).not_to be_nil
    expect(alplus_index).to be > show_exceptions_index
  end

  it "captures an unhandled exception raised by a controller action, with the app still returning its normal error response" do
    get "/boom"

    expect(last_response.status).to eq(500)
    expect(Alplus.test_transport.envelopes.length).to eq(1)
    item = Alplus.test_transport.envelopes.first[:items].first
    expect(item[:exception][:type]).to eq("RuntimeError")
    expect(item[:exception][:value]).to eq("boom from the controller")
    expect(item[:mechanism]).to eq("rack.middleware")
  end

  it "captures nothing for a request that does not raise" do
    get "/ok"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq("ok")
    expect(Alplus.test_transport.envelopes).to be_empty
  end

  it "sets app_dirs from Rails.root so controller frames are in_app" do
    expect(@railtie_detected_app_dirs).to eq([Rails.root.to_s])
  end
end
