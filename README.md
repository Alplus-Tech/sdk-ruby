# postdeploy

> **Retired.** This SDK is no longer maintained and receives no updates. PostDeploy accepts events from the official Sentry SDKs. Install `sentry-ruby` and use the DSN that PostDeploy shows for your source. See https://postdeploy.dev/docs.

Error reporting for [PostDeploy Observe](https://postdeploy.dev). Ruby and Rails.

Zero runtime dependencies: `Net::HTTP` and the stdlib only.

Setup guide: [Ruby and Rails error tracking](https://postdeploy.dev/docs/observe/ruby).

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
PostDeploy.heartbeat(token, state: "fail", ping_id: "nightly-2026-08-30")
```

Heartbeat calls never raise. Each call makes at most two attempts and reuses
one `ping_id` across retries. The server deduplicates a supplied ID per monitor
for 24 hours. Transport failures, `408`, `429`, and `5xx` responses retry only.
Each attempt is bounded to five seconds. Delta-seconds `Retry-After` is capped
at two seconds; other retries use jittered backoff around 500ms. Diagnostics
never include the full heartbeat token.

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
