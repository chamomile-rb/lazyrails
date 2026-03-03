# frozen_string_literal: true

RSpec.describe LazyRails::CommandLogOverlay do
  let(:command_log) { LazyRails::CommandLog.new }
  subject(:overlay) { described_class.new(command_log) }

  def add_entries(n)
    n.times do |i|
      entry = LazyRails::CommandEntry.new(
        command: "cmd#{i}",
        exit_code: 0,
        stdout: "out#{i}",
        stderr: "",
        duration_ms: 100,
        timestamp: Time.now
      )
      command_log.add(entry)
    end
  end

  describe "#show / #hide" do
    it "starts hidden" do
      expect(overlay).not_to be_visible
    end

    it "becomes visible after show" do
      overlay.show
      expect(overlay).to be_visible
      expect(overlay.cursor).to eq(0)
      expect(overlay.detail).to be_nil
    end

    it "hides after hide" do
      overlay.show
      overlay.hide
      expect(overlay).not_to be_visible
    end

    it "resets cursor and detail on show" do
      add_entries(3)
      overlay.show
      overlay.handle_key("j")
      overlay.handle_key(:enter)
      overlay.show
      expect(overlay.cursor).to eq(0)
      expect(overlay.detail).to be_nil
    end
  end

  describe "#handle_key" do
    before do
      add_entries(5)
      overlay.show
    end

    it "moves cursor down with j" do
      overlay.handle_key("j")
      expect(overlay.cursor).to eq(1)
    end

    it "moves cursor down with :down" do
      overlay.handle_key(:down)
      expect(overlay.cursor).to eq(1)
    end

    it "moves cursor up with k" do
      overlay.handle_key("j")
      overlay.handle_key("j")
      overlay.handle_key("k")
      expect(overlay.cursor).to eq(1)
    end

    it "moves cursor up with :up" do
      overlay.handle_key("j")
      overlay.handle_key(:up)
      expect(overlay.cursor).to eq(0)
    end

    it "clamps cursor at bottom" do
      10.times { overlay.handle_key("j") }
      expect(overlay.cursor).to eq(4)
    end

    it "clamps cursor at top" do
      overlay.handle_key("k")
      expect(overlay.cursor).to eq(0)
    end

    it "clears detail on cursor move" do
      overlay.handle_key(:enter)
      expect(overlay.detail).not_to be_nil
      overlay.handle_key("j")
      expect(overlay.detail).to be_nil
    end

    it "selects detail on enter" do
      overlay.handle_key("j")
      overlay.handle_key(:enter)
      expect(overlay.detail).to eq(command_log.entries[1])
    end

    it "hides on escape" do
      overlay.handle_key(:escape)
      expect(overlay).not_to be_visible
    end

    it "hides on L" do
      overlay.handle_key("L")
      expect(overlay).not_to be_visible
    end

    it "returns :quit on q" do
      result = overlay.handle_key("q")
      expect(result).to eq(:quit)
    end

    it "returns nil for navigation keys" do
      expect(overlay.handle_key("j")).to be_nil
      expect(overlay.handle_key("k")).to be_nil
      expect(overlay.handle_key(:enter)).to be_nil
      expect(overlay.handle_key(:escape)).to be_nil
    end
  end

  describe "#handle_key with empty log" do
    it "clamps cursor at 0" do
      overlay.show
      overlay.handle_key("j")
      expect(overlay.cursor).to eq(0)
    end
  end
end
