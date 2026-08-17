# frozen_string_literal: true

require "spec_helper"
require "active_support"
require "active_support/isolated_execution_state"
require "active_support/notifications"
require_relative "../../lib/alplus/notifications_subscriber"

RSpec.describe Alplus::NotificationsSubscriber do
  # Subscribed to the real, process-global `ActiveSupport::Notifications`
  # notifier exactly ONCE for this whole file (matching how a real Rails
  # boot calls `install!` exactly once) -- calling `reset!` + `install!`
  # per-example would stack a fresh duplicate subscription on the shared
  # notifier every example, since the underlying `subscribe` call has no
  # matching per-example `unsubscribe` here.
  before(:all) { Alplus::NotificationsSubscriber.install! }

  before do
    Alplus::Scope.current.instance_variable_set(:@breadcrumbs, [])
  end

  after do
    Thread.current[:alplus_scope] = nil
  end

  it "adds a query breadcrumb for an sql.active_record notification" do
    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT * FROM users WHERE id = ?", name: "User Load") do
      # simulated query
    end

    crumb = Alplus::Scope.current.breadcrumbs.last
    expect(crumb[:category]).to eq("query")
    expect(crumb[:message]).to eq("SELECT * FROM users WHERE id = ?")
  end

  it "skips SCHEMA-name sql notifications" do
    before_count = Alplus::Scope.current.breadcrumbs.length

    ActiveSupport::Notifications.instrument("sql.active_record", sql: "PRAGMA foo", name: "SCHEMA") {}

    expect(Alplus::Scope.current.breadcrumbs.length).to eq(before_count)
  end

  it "adds an http breadcrumb for a process_action.action_controller notification" do
    ActiveSupport::Notifications.instrument(
      "process_action.action_controller",
      controller: "WidgetsController", action: "show", status: 200, method: "GET"
    ) {}

    crumb = Alplus::Scope.current.breadcrumbs.last
    expect(crumb[:category]).to eq("http")
    expect(crumb[:message]).to eq("WidgetsController#show")
    expect(crumb[:data][:status]).to eq(200)
  end

  it "never leaks bind values into the sql breadcrumb data" do
    ActiveSupport::Notifications.instrument(
      "sql.active_record",
      sql: "SELECT * FROM users WHERE password = ?", name: "User Load",
      binds: [double("bind", value: "hunter2")]
    ) {}

    crumb = Alplus::Scope.current.breadcrumbs.last
    expect(crumb[:data]).not_to have_key(:binds)
    expect(JSON.generate(crumb)).not_to include("hunter2")
  end

  it "does nothing when config.breadcrumbs_enabled is false" do
    Alplus.configuration.breadcrumbs_enabled = false
    before_count = Alplus::Scope.current.breadcrumbs.length

    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT 1", name: "Query") {}

    expect(Alplus::Scope.current.breadcrumbs.length).to eq(before_count)
  end

  it "is a no-op to install! a second (or third) time (idempotent subscription)" do
    3.times { Alplus::NotificationsSubscriber.install! }

    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT 1", name: "Query") {}

    matching = Alplus::Scope.current.breadcrumbs.select { |c| c[:message] == "SELECT 1" }
    expect(matching.length).to eq(1)
  end
end
