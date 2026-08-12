# frozen_string_literal: true

require "json"
require "time"

module Alplus
  # Builds the `POST /e/errors` wire envelope. Mirrors
  # `packages/sdk/src/core/observe/{client,envelope}.ts` (the TypeScript
  # SDK) and the Elixir SDK (#13): `{header: {key, sdk, sent_at}, items: [...]}`
  # with one item per request. Kept additive-only per docs/BUILD.md §5 —
  # every field here already exists in the accepted server shape.
  #
  # Per-field caps mirror the JS SDK's own write-boundary caps
  # (`envelope.ts`'s `MAX_*` constants) so an oversized field is trimmed
  # HERE, per field, and the event still sends — the same trade-off the JS
  # SDK makes. `Transport::MAX_ENVELOPE_BYTES`'s whole-envelope check stays
  # a last-resort safety net for the case these per-field caps still don't
  # fit (should be unreachable in practice, same as the JS SDK's own
  # comment on its equivalent guard).
  module Envelope
    MAX_ENVELOPE_BYTES = 1_048_576
    MAX_MESSAGE_CHARS = 4_096
    MAX_EXCEPTION_VALUE_CHARS = 4_096
    MAX_STACK_TRACE_CHARS = 16_384
    MAX_CONTEXT_CHARS = 8_192
    MAX_TAGS_CHARS = 4_096
    SERVER_MAX_BREADCRUMBS = 100
    MAX_BREADCRUMB_MESSAGE_CHARS = 2_048
    MAX_BREADCRUMB_CATEGORY_CHARS = 128

    module_function

    def wrap(config:, item:)
      {
        header: {
          key: config.key,
          sdk: { name: Alplus::SDK_NAME, version: Alplus::VERSION, platform: "ruby" },
          sent_at: Time.now.utc.iso8601
        },
        items: [item]
      }
    end

    def exception_item(id:, exception:, config:, level: "error", context: nil, tags: nil, breadcrumbs: nil, mechanism: "generic")
      frames = Stack.frames_for(exception, app_dirs: config.app_dirs)
      exc = { type: exception.class.name, value: cap_text(exception.message.to_s, MAX_EXCEPTION_VALUE_CHARS) }
      capped_frames = cap_frames(frames, MAX_STACK_TRACE_CHARS)
      exc[:stacktrace] = { frames: capped_frames } unless capped_frames.empty?

      base_item(id: id, type: "exception", level: level, config: config, mechanism: mechanism, context: context, tags: tags, breadcrumbs: breadcrumbs)
        .merge(exception: exc)
    end

    def message_item(id:, message:, config:, level: "info", context: nil, tags: nil, breadcrumbs: nil, mechanism: "generic")
      base_item(id: id, type: "message", level: level, config: config, mechanism: mechanism, context: context, tags: tags, breadcrumbs: breadcrumbs)
        .merge(message: cap_text(message.to_s, MAX_MESSAGE_CHARS))
    end

    def base_item(id:, type:, level:, config:, mechanism:, context:, tags:, breadcrumbs:)
      item = {
        id: id,
        type: type,
        timestamp: Time.now.utc.iso8601,
        level: level.to_s,
        release: config.release,
        environment: config.environment,
        mechanism: mechanism
      }
      item[:contexts] = cap_context({ extra: context }, MAX_CONTEXT_CHARS) if context && !context.empty?
      capped_tags = cap_tags(tags, MAX_TAGS_CHARS)
      item[:tags] = capped_tags if capped_tags
      capped_crumbs = cap_breadcrumbs(breadcrumbs, SERVER_MAX_BREADCRUMBS)
      item[:breadcrumbs] = capped_crumbs if capped_crumbs && !capped_crumbs.empty?
      item.compact
    end

    # Truncates a string to at most `max_length` characters. Passes
    # non-strings through `#to_s` first; callers already do this, kept
    # defensive here since a truncated field is safer than a raise.
    def cap_text(value, max_length)
      value = value.to_s
      return value if value.length <= max_length

      value[0, max_length]
    end

    # Caps a JSON-ish hash by its serialized size. A value whose
    # serialization exceeds `max_chars` is REPLACED by a small truncation
    # marker rather than cut mid-string, mirroring the JS SDK's
    # `capContext` — a partial JSON string is unparseable, which is worse
    # than a shorter one.
    def cap_context(value, max_chars)
      serialized = JSON.generate(value)
      return value if serialized.bytesize <= max_chars

      { _truncated: true, _original_chars: serialized.bytesize }
    end

    # Drops the tags object entirely (with a debug-log warning) rather than
    # send a truncated `Hash` that would no longer round-trip as one — same
    # trade-off the JS SDK's `capTags` makes. Returns `nil` for a `nil`/
    # empty input so the caller can omit the key.
    def cap_tags(tags, max_chars)
      return nil if tags.nil? || tags.empty?
      return tags if JSON.generate(tags).bytesize <= max_chars

      nil
    end

    # Drops trailing frames until the serialized array fits `max_chars`,
    # mirroring the JS SDK's `capFrames`/the server's `capFramesToBudget`.
    #
    # Binary-searches the cut point (O(log n) `JSON.generate` calls)
    # instead of popping one frame and re-serializing the whole array per
    # pop (O(n) calls, each itself O(n)) — a deep recursive backtrace can
    # carry thousands of frames, where the naive approach is noticeably
    # slow.
    def cap_frames(frames, max_chars)
      return frames if frames.empty? || JSON.generate(frames).bytesize <= max_chars

      low = 0
      high = frames.length - 1
      while low < high
        mid = (low + high + 1) / 2
        if JSON.generate(frames.first(mid)).bytesize <= max_chars
          low = mid
        else
          high = mid - 1
        end
      end
      frames.first(low)
    end

    # Caps breadcrumb count to the server's own ceiling (keeping the most
    # recent ones) and per-breadcrumb message/category length.
    def cap_breadcrumbs(breadcrumbs, max_count)
      return nil if breadcrumbs.nil?

      breadcrumbs.last(max_count).map do |crumb|
        crumb = crumb.dup
        crumb[:message] = cap_text(crumb[:message], MAX_BREADCRUMB_MESSAGE_CHARS) if crumb[:message]
        crumb[:category] = cap_text(crumb[:category], MAX_BREADCRUMB_CATEGORY_CHARS) if crumb[:category]
        crumb
      end
    end
  end
end
