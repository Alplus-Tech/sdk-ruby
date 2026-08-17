# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

RSpec.describe "post-error log window (issue #47)" do
  def configure(window_ms)
    Alplus.configure do |c|
      c.test_mode = true
      c.post_error_log_window_ms = window_ms
    end
  end

  def attached_logger
    logger = Logger.new(StringIO.new)
    Alplus::LoggerBreadcrumbs.attach(logger)
    logger
  end

  it "a log line after capture joins the event, marked after_error, once sealed" do
    configure(10_000)
    logger = attached_logger

    Alplus.capture_exception(RuntimeError.new("boom"))
    expect(Alplus.test_transport.envelopes).to be_empty

    logger.error("RuntimeError (boom): rendered 500")
    Alplus.flush

    item = Alplus.test_transport.envelopes.first[:items].first
    after_crumb = item[:breadcrumbs].find { |c| c[:message] == "RuntimeError (boom): rendered 500" }
    expect(after_crumb[:data]).to eq(after_error: true)
  end

  it "the sealer delivers on its own once the window elapses" do
    configure(30)
    Alplus.capture_exception(RuntimeError.new("boom"))
    expect(Alplus.test_transport.envelopes).to be_empty

    deadline = Time.now + 2
    sleep(0.01) while Alplus.test_transport.envelopes.empty? && Time.now < deadline
    expect(Alplus.test_transport.envelopes.length).to eq(1)
  end

  it "another thread's log lines never join this thread's pending event" do
    configure(10_000)
    logger = attached_logger

    Alplus.capture_exception(RuntimeError.new("boom"))
    Thread.new { logger.error("other request noise") }.join
    Alplus.flush

    item = Alplus.test_transport.envelopes.first[:items].first
    crumbs = item[:breadcrumbs] || []
    expect(crumbs.none? { |c| c[:message] == "other request noise" }).to be(true)
  end

  it "after-error appends are capped at 20" do
    configure(10_000)
    logger = attached_logger

    Alplus.capture_exception(RuntimeError.new("boom"))
    30.times { |n| logger.info("after line #{n}") }
    Alplus.flush

    item = Alplus.test_transport.envelopes.first[:items].first
    after = item[:breadcrumbs].select { |c| c[:data] && c[:data][:after_error] }
    expect(after.length).to eq(20)
  end

  it "window 0 delivers synchronously, exactly the old behavior" do
    configure(0)
    Alplus.capture_exception(RuntimeError.new("boom"))
    expect(Alplus.test_transport.envelopes.length).to eq(1)
  end

  it "test mode defaults the window to 0 when unset" do
    Alplus.configure { |c| c.test_mode = true }
    expect(Alplus.configuration.resolved_post_error_log_window_ms).to eq(0)
    Alplus.capture_exception(RuntimeError.new("boom"))
    expect(Alplus.test_transport.envelopes.length).to eq(1)
  end

  it "the middleware capture path picks up Rails-style post-raise logging" do
    configure(10_000)
    logger = attached_logger
    raising_app = ->(_env) { raise "boom from the app" }
    middleware = Alplus::RackMiddleware.new(raising_app)

    begin
      middleware.call({})
    rescue RuntimeError
      # What ActionDispatch::DebugExceptions does next, on the same thread:
      logger.fatal("RuntimeError (boom from the app):")
    end

    Alplus.flush
    item = Alplus.test_transport.envelopes.first[:items].first
    after_crumb = item[:breadcrumbs].find { |c| c[:message] == "RuntimeError (boom from the app):" }
    expect(after_crumb[:level]).to eq("fatal")
    expect(after_crumb[:data]).to eq(after_error: true)
  end
end
