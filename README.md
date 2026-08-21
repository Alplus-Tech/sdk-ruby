# postdeploy

Error reporting for [PostDeploy Observe](https://postdeploy.dev). Ruby and Rails.

Zero runtime dependencies: `Net::HTTP` and the stdlib only.

## Install

```ruby
# Gemfile
gem "postdeploy"
```

Set `POSTDEPLOY_API_KEY` (an ingest key with the `ingest` scope).

## Rails

Add the gem. The railtie installs `PostDeploy::RackMiddleware` and captures
unhandled exceptions. No further wiring is required.

Identify the current user in a `before_action`:

```ruby
PostDeploy.set_user(id: user.id, email: user.email)
PostDeploy.set_tag("org_id", org.id)
```

## Capture

```ruby
begin
  risky_operation!
rescue => e
  PostDeploy.capture_exception(e, context: { order_id: order.id })
end

PostDeploy.capture_message("low disk space", level: "warning")
```

Both methods return an `err_` event id and never raise.

## Heartbeat

```ruby
PostDeploy.heartbeat(token)
PostDeploy.heartbeat(token, state: "fail")
```

## Plain Rack

```ruby
use PostDeploy::RackMiddleware
```

## Config

The key is read from `POSTDEPLOY_API_KEY` by default. It is never logged.

```ruby
PostDeploy.configure do |config|
  config.environment = "production"
  config.release = ENV["GIT_SHA"]
  config.before_send = ->(item) { item }
end
```

`before_send` receives the built item. Return `nil` to drop it. A raise
sends the original item.

## Tests

```ruby
PostDeploy.configure { |c| c.test_mode = true }

PostDeploy.capture_exception(error)
PostDeploy.flush
item = PostDeploy::Testing.events.first
```

Nothing hits the network. Set `config.enabled = false` to disable capture.

## Development

```
cd sdks/ruby
bundle install
export ALPLUS_CONTRACT_DIR=../../sdks/contract
bundle exec rspec
```
