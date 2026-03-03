# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe LazyRails::Parsers::GemfileLock do
  describe ".parse" do
    it "returns empty array for non-existent file" do
      expect(described_class.parse("/nonexistent/Gemfile.lock")).to eq([])
    end

    it "parses a lockfile and returns sorted gems" do
      Dir.mktmpdir do |dir|
        gemfile = File.join(dir, "Gemfile")
        lockfile = File.join(dir, "Gemfile.lock")

        File.write(gemfile, <<~GEMFILE)
          source "https://rubygems.org"
          gem "rake"
          group :test do
            gem "rspec"
          end
        GEMFILE

        File.write(lockfile, <<~LOCKFILE)
          GEM
            remote: https://rubygems.org/
            specs:
              rake (13.0.6)
              rspec (3.12.0)

          PLATFORMS
            ruby

          DEPENDENCIES
            rake
            rspec

          BUNDLED WITH
            2.4.10
        LOCKFILE

        gems = described_class.parse(lockfile)

        expect(gems.size).to eq(2)
        expect(gems.map(&:name)).to eq(%w[rake rspec])
        expect(gems[0].version).to eq("13.0.6")
        expect(gems[1].version).to eq("3.12.0")
      end
    end

    it "detects gem groups from Gemfile" do
      Dir.mktmpdir do |dir|
        gemfile = File.join(dir, "Gemfile")
        lockfile = File.join(dir, "Gemfile.lock")

        File.write(gemfile, <<~GEMFILE)
          source "https://rubygems.org"
          gem "rails"
          group :development, :test do
            gem "rspec"
          end
        GEMFILE

        File.write(lockfile, <<~LOCKFILE)
          GEM
            remote: https://rubygems.org/
            specs:
              rails (7.1.3)
              rspec (3.12.0)

          PLATFORMS
            ruby

          DEPENDENCIES
            rails
            rspec

          BUNDLED WITH
            2.4.10
        LOCKFILE

        gems = described_class.parse(lockfile)
        rails_gem = gems.find { |g| g.name == "rails" }
        rspec_gem = gems.find { |g| g.name == "rspec" }

        expect(rails_gem.groups).to eq([:default])
        expect(rspec_gem.groups).to contain_exactly(:development, :test)
      end
    end
  end
end
