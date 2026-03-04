# frozen_string_literal: true

RSpec.describe LazyRails::LogWatcher do
  let(:project_dir) { Dir.mktmpdir }
  let(:log_dir) { File.join(project_dir, "log") }
  let(:log_path) { File.join(log_dir, "development.log") }
  let(:project) { double("Project", dir: project_dir) }

  before { Dir.mkdir(log_dir) }
  after { FileUtils.remove_entry(project_dir) }

  describe "#initialize" do
    it "starts in a clean state" do
      watcher = described_class.new(project)
      expect(watcher).not_to be_changed
      expect(watcher.take_entries).to eq([])
    end
  end

  describe "#start" do
    it "does not start if log file does not exist" do
      watcher = described_class.new(project)
      watcher.start
      # Should not raise, just silently skip
      watcher.stop
    end
  end

  describe "#clear" do
    it "clears entries and dirty flag" do
      watcher = described_class.new(project)
      # Access internal state for testing
      watcher.instance_variable_set(:@entries, [double("entry")])
      watcher.instance_variable_set(:@dirty, true)
      watcher.clear
      expect(watcher).not_to be_changed
      expect(watcher.take_entries).to eq([])
    end
  end

  describe "#take_entries" do
    it "returns entries and resets dirty flag" do
      watcher = described_class.new(project)
      entry = double("entry")
      watcher.instance_variable_set(:@entries, [entry])
      watcher.instance_variable_set(:@dirty, true)

      taken = watcher.take_entries
      expect(taken).to eq([entry])
      expect(watcher).not_to be_changed
      expect(watcher.take_entries).to eq([])
    end
  end
end
