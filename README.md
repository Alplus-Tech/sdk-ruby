# alplus-ruby

Error reporting for [AL+ Observe](https://alplus.dev). Ruby and Rails.

Zero runtime dependencies: `Net::HTTP` and the stdlib only.

## Install

```ruby
# Gemfile
gem "alplus-ruby", require: "alplus"
```

Set `ALPLUS_KEY` (an ingest key with the `ingest` scope).

## Rails

Add the gem. The railtie installs `Alplus::RackMiddleware` and captures
unhandled exceptions. No further wiring is required.

Identify the current user in a `before_action`:

```ruby
Alplus.set_user(id: user.id, email: user.email)
Alplus.set_tag("org_id", org.id)
```

## Capture

```ruby
begin
  risky_operation!
rescue => e
  Alplus.capture_exception(e, context: { order_id: order.id })
end

Alplus.capture_message("low disk space", level: "warning")
```

Both methods return an `err_` event id and never raise.

## Heartbeat

```ruby
Alplus.heartbeat(token)
Alplus.heartbeat(token, state: "fail")
```

## Plain Rack

```ruby
use Alplus::RackMiddleware
```

## Config

The key is read from `ALPLUS_KEY` by default. It is never logged.

```ruby
Alplus.configure do |config|
  config.environment = "production"
  config.release = ENV["GIT_SHA"]
  config.before_send = ->(item) { item }
end
```

`before_send` receives the built item. Return `nil` to drop it. A raise
sends the original item.

## Tests

```ruby
Alplus.configure { |c| c.test_mode = true }

Alplus.capture_exception(error)
Alplus.flush
item = Alplus::Testing.events.first
```

Nothing hits the network. Set `config.enabled = false` to disable capture.

## Development

```
cd sdks/ruby
bundle install
export ALPLUS_CONTRACT_DIR=../../sdks/contract
bundle exec rspec
```
