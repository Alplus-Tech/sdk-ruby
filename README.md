# alplus-ruby

Error reporting for [AL+ Observe](https://alplus.dev) — Ruby and Rails.

Zero runtime dependencies: `Net::HTTP` and the stdlib only.

## Install

```ruby
# Gemfile
gem "alplus-ruby", require: "alplus"
```

## Configure

```ruby
Alplus.configure do |config|
  config.key = ENV["ALPLUS_KEY"]        # alp_... ingest key with the `ingest` scope
  config.environment = "production"     # default: RAILS_ENV / RACK_ENV / "production"
  config.release = ENV["GIT_SHA"]
end
```

The key is read from `ALPLUS_KEY` by default. It is never logged or
included in `Configuration#inspect`.

## Capture

```ruby
begin
  risky_operation!
rescue => e
  Alplus.capture_exception(e, context: { order_id: order.id })
end

Alplus.capture_message("low disk space", level: "warning")
```

Both methods return the client-generated `err_` event id synchronously and
never raise, even if AL+ is unreachable.

## Rails

Add the gem; a railtie installs `Alplus::RackMiddleware` automatically and
captures every unhandled exception. No further wiring is required.

## Plain Rack

```ruby
use Alplus::RackMiddleware
```

## Test / development

```ruby
Alplus.configure { |c| c.test_mode = true }
```

In test mode, events are recorded in memory (`Alplus.test_transport.envelopes`)
and never sent over the network. Set `config.enabled = false` to disable
capture entirely.

## Development

```
cd sdks/ruby
bundle install
bundle exec rspec
```
