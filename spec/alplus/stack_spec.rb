# frozen_string_literal: true

require "spec_helper"

RSpec.describe Alplus::Stack do
  def raise_in_app
    raise "boom"
  rescue StandardError => e
    e
  end

  describe ".frames_for" do
    it "maps the backtrace to frames with file/lineno/function" do
      exception = raise_in_app
      frames = described_class.frames_for(exception, app_dirs: [__dir__])

      expect(frames).not_to be_empty
      first = frames.first
      expect(first[:file]).to eq(__FILE__)
      expect(first[:lineno]).to be_a(Integer)
      expect(first[:function]).to be_a(String)
    end

    it "marks frames under app_dirs as in_app" do
      exception = raise_in_app
      frames = described_class.frames_for(exception, app_dirs: [__dir__])

      expect(frames.first[:in_app]).to be true
    end

    it "marks frames outside app_dirs as not in_app" do
      exception = raise_in_app
      frames = described_class.frames_for(exception, app_dirs: ["/somewhere/else"])

      expect(frames.first[:in_app]).to be false
    end

    it "marks gem/library paths as not in_app even with no app_dirs configured" do
      expect(described_class.in_app?("/usr/lib/ruby/gems/3.3.0/gems/rack-3.0.0/lib/rack/builder.rb", [])).to be false
    end

    it "treats every path as in_app when app_dirs is empty and the path isn't a library path" do
      expect(described_class.in_app?("/home/app/app/controllers/widgets_controller.rb", [])).to be true
    end

    it "returns an empty array for an exception with no backtrace" do
      expect(described_class.frames_for(StandardError.new("no trace"))).to eq([])
    end
  end
end
