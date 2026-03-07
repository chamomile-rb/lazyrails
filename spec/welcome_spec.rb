# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe LazyRails::WelcomeOverlay do
  let(:overlay) { described_class.new }

  describe "#show / #hide" do
    it "starts hidden" do
      expect(overlay).not_to be_visible
    end

    it "becomes visible after show" do
      overlay.show
      expect(overlay).to be_visible
    end

    it "hides after hide" do
      overlay.show
      overlay.hide
      expect(overlay).not_to be_visible
    end
  end

  describe "#handle_key" do
    before { overlay.show }

    it "scrolls down with j" do
      expect(overlay.handle_key("j")).to be_nil
    end

    it "scrolls up with k" do
      expect(overlay.handle_key("k")).to be_nil
    end

    it "returns :dismiss on Enter" do
      expect(overlay.handle_key(:enter)).to eq(:dismiss)
    end

    it "returns :dismiss_forever on !" do
      expect(overlay.handle_key("!")).to eq(:dismiss_forever)
    end

    it "returns :quit on q" do
      expect(overlay.handle_key("q")).to eq(:quit)
    end
  end

  describe "#render" do
    before { overlay.show }

    it "renders without error" do
      result = overlay.render(width: 80, height: 24)
      expect(result).to be_a(String)
      expect(result).to include("Welcome")
    end

    it "includes key instructions" do
      result = overlay.render(width: 80, height: 40)
      expect(result).to include("Tab")
      expect(result).to include("Enter")
    end
  end
end

RSpec.describe LazyRails::UserSettings do
  it "defaults to welcome not seen" do
    Dir.mktmpdir do |dir|
      settings = described_class.new(config_dir: dir)
      expect(settings).not_to be_welcome_seen
    end
  end

  it "persists welcome_seen across instances" do
    Dir.mktmpdir do |dir|
      settings = described_class.new(config_dir: dir)
      settings.mark_welcome_seen!

      settings2 = described_class.new(config_dir: dir)
      expect(settings2).to be_welcome_seen
    end
  end
end
