# frozen_string_literal: true

RSpec.describe LazyRails::CommandLog do
  def make_entry(command:, exit_code: 0, duration_ms: 100)
    LazyRails::CommandEntry.new(
      command: command,
      exit_code: exit_code,
      duration_ms: duration_ms,
      timestamp: Time.now,
      stdout: "",
      stderr: ""
    )
  end

  describe "#add" do
    it "adds an entry" do
      log = described_class.new
      entry = make_entry(command: "bin/rails db:migrate")
      log.add(entry)

      expect(log.size).to eq(1)
      expect(log.last_entry).to eq(entry)
    end

    it "caps at MAX_ENTRIES" do
      log = described_class.new
      (described_class::MAX_ENTRIES + 10).times do |i|
        log.add(make_entry(command: "cmd #{i}"))
      end

      expect(log.size).to eq(described_class::MAX_ENTRIES)
    end

    it "drops oldest entries when full" do
      log = described_class.new
      (described_class::MAX_ENTRIES + 5).times do |i|
        log.add(make_entry(command: "cmd #{i}"))
      end

      expect(log.entries.first.command).to eq("cmd 5")
    end
  end

  describe "#empty?" do
    it "returns true when no entries" do
      expect(described_class.new).to be_empty
    end

    it "returns false after adding" do
      log = described_class.new
      log.add(make_entry(command: "test"))
      expect(log).not_to be_empty
    end
  end

  describe "#reversible?" do
    it "returns true for rails generate" do
      log = described_class.new
      entry = make_entry(command: "bin/rails generate migration CreateUsers")
      expect(log.reversible?(entry)).to be true
    end

    it "returns true for db:migrate" do
      log = described_class.new
      entry = make_entry(command: "bin/rails db:migrate")
      expect(log.reversible?(entry)).to be true
    end

    it "returns true for db:migrate:up" do
      log = described_class.new
      entry = make_entry(command: "bin/rails db:migrate:up VERSION=20240101")
      expect(log.reversible?(entry)).to be true
    end

    it "returns false for failed commands" do
      log = described_class.new
      entry = make_entry(command: "bin/rails generate migration Foo", exit_code: 1)
      expect(log.reversible?(entry)).to be false
    end

    it "returns false for db:rollback" do
      log = described_class.new
      entry = make_entry(command: "bin/rails db:rollback")
      expect(log.reversible?(entry)).to be false
    end

    it "returns false for db:migrate:down" do
      log = described_class.new
      entry = make_entry(command: "bin/rails db:migrate:down VERSION=123")
      expect(log.reversible?(entry)).to be false
    end
  end

  describe "#reverse_command" do
    it "reverses generate to destroy" do
      log = described_class.new
      entry = make_entry(command: "bin/rails generate migration CreateUsers")
      expect(log.reverse_command(entry)).to eq("bin/rails destroy migration CreateUsers")
    end

    it "reverses db:migrate to db:rollback" do
      log = described_class.new
      entry = make_entry(command: "bin/rails db:migrate")
      expect(log.reverse_command(entry)).to eq("bin/rails db:rollback")
    end

    it "reverses db:migrate:up to db:migrate:down" do
      log = described_class.new
      entry = make_entry(command: "bin/rails db:migrate:up VERSION=20240101")
      expect(log.reverse_command(entry)).to eq("bin/rails db:migrate:down VERSION=20240101")
    end

    it "returns nil for non-reversible commands" do
      log = described_class.new
      entry = make_entry(command: "bundle install")
      expect(log.reverse_command(entry)).to be_nil
    end
  end

  describe "#last_reversible" do
    it "returns nil when no reversible entries" do
      log = described_class.new
      log.add(make_entry(command: "bundle install"))
      expect(log.last_reversible).to be_nil
    end

    it "returns the most recent reversible entry" do
      log = described_class.new
      log.add(make_entry(command: "bin/rails generate migration One"))
      log.add(make_entry(command: "bundle install"))
      log.add(make_entry(command: "bin/rails db:migrate"))

      expect(log.last_reversible.command).to eq("bin/rails db:migrate")
    end
  end

  describe "#clear" do
    it "removes all entries" do
      log = described_class.new
      log.add(make_entry(command: "test"))
      log.clear
      expect(log).to be_empty
    end
  end
end
