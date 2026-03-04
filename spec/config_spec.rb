# frozen_string_literal: true

RSpec.describe LazyRails::Config do
  describe ".load" do
    it "returns empty config when no file exists" do
      config = described_class.load("/nonexistent/path")
      expect(config).to be_empty
      expect(config.custom_commands).to eq([])
    end

    it "parses custom commands from YAML" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".lazyrails.yml"), <<~YAML)
          custom_commands:
            - name: Deploy
              key: d
              command: bin/deploy
              confirmation: yellow
            - name: Seed
              key: s
              command: bin/rails db:seed
        YAML

        config = described_class.load(dir)
        expect(config).not_to be_empty
        expect(config.custom_commands.size).to eq(2)

        deploy = config.custom_commands[0]
        expect(deploy.name).to eq("Deploy")
        expect(deploy.key).to eq("d")
        expect(deploy.command).to eq("bin/deploy")
        expect(deploy.confirmation_tier).to eq(:yellow)

        seed = config.custom_commands[1]
        expect(seed.name).to eq("Seed")
        expect(seed.confirmation_tier).to eq(:green)
      end
    end

    it "returns empty config for invalid YAML" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".lazyrails.yml"), "{{invalid yaml")
        config = described_class.load(dir)
        expect(config).to be_empty
      end
    end

    it "returns empty config when custom_commands key is missing" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".lazyrails.yml"), "other_key: value\n")
        config = described_class.load(dir)
        expect(config).to be_empty
      end
    end
  end

  describe LazyRails::Config::CustomCommand do
    let(:cmd) { described_class.new(name: "Test", key: "t", command: "echo hi", confirmation: nil) }

    it "returns green tier when no confirmation set" do
      expect(cmd.confirmation_tier).to eq(:green)
    end

    it "returns the configured tier" do
      red_cmd = described_class.new(name: "Drop", key: "x", command: "db:drop", confirmation: "red")
      expect(red_cmd.confirmation_tier).to eq(:red)
    end

    it "renders name as to_s" do
      expect(cmd.to_s).to eq("Test")
    end
  end
end
