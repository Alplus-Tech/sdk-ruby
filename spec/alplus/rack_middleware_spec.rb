# frozen_string_literal: true

require "spec_helper"

RSpec.describe Alplus::RackMiddleware do
  before do
    Alplus.configure { |c| c.test_mode = true }
  end

  it "captures an exception raised by the wrapped app and re-raises it" do
    raising_app = ->(_env) { raise "boom from the app" }
    middleware = described_class.new(raising_app)

    expect { middleware.call({}) }.to raise_error(RuntimeError, "boom from the app")

    expect(Alplus.test_transport.envelopes.length).to eq(1)
    item = Alplus.test_transport.envelopes.first[:items].first
    expect(item[:exception][:type]).to eq("RuntimeError")
    expect(item[:mechanism]).to eq("rack.middleware")
  end

  it "passes through untouched when the app does not raise" do
    ok_app = ->(env) { [200, {}, ["ok: #{env["PATH_INFO"]}"]] }
    middleware = described_class.new(ok_app)

    status, _headers, body = middleware.call("PATH_INFO" => "/widgets")

    expect(status).to eq(200)
    expect(body).to eq(["ok: /widgets"])
    expect(Alplus.test_transport.envelopes).to be_empty
  end

  it "does not capture a process-control exception like SystemExit" do
    exiting_app = ->(_env) { raise SystemExit }
    middleware = described_class.new(exiting_app)

    expect { middleware.call({}) }.to raise_error(SystemExit)
    expect(Alplus.test_transport.envelopes).to be_empty
  end
end
