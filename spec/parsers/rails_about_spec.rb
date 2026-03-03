# frozen_string_literal: true

RSpec.describe LazyRails::Parsers::RailsAbout do
  describe ".parse" do
    it "returns empty hash for nil input" do
      expect(described_class.parse(nil)).to eq({})
    end

    it "returns empty hash for empty string" do
      expect(described_class.parse("")).to eq({})
    end

    it "parses standard rails about output" do
      output = <<~OUTPUT
        About your application's environment
        Rails version             7.1.3
        Ruby version              ruby 3.2.2 (2023-03-30 revision e51014f9c0) [arm64-darwin22]
        RubyGems version          3.4.10
        Rack version              3.0.8
        Environment               development
        Database adapter          sqlite3
      OUTPUT

      result = described_class.parse(output)

      expect(result["Rails version"]).to eq("7.1.3")
      expect(result["Environment"]).to eq("development")
      expect(result["Database adapter"]).to eq("sqlite3")
      expect(result).not_to have_key("About your application's environment")
    end

    it "handles multi-word values" do
      output = <<~OUTPUT
        Ruby version              ruby 3.2.2 (2023-03-30 revision e51014f9c0) [arm64-darwin22]
      OUTPUT

      result = described_class.parse(output)
      expect(result["Ruby version"]).to eq("ruby 3.2.2 (2023-03-30 revision e51014f9c0) [arm64-darwin22]")
    end

    it "skips blank lines" do
      output = "Rails version             7.1.3\n\n\nRuby version              3.2.2\n"
      result = described_class.parse(output)
      expect(result.keys).to eq(["Rails version", "Ruby version"])
    end
  end
end
