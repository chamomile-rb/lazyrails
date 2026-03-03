# frozen_string_literal: true

RSpec.describe LazyRails::Confirmation do
  describe "tier detection" do
    it "detects red tier for db:drop" do
      c = described_class.new(command: "bin/rails db:drop")
      expect(c.tier).to eq(:red)
      expect(c).to be_red
    end

    it "detects red tier for db:reset" do
      c = described_class.new(command: "bin/rails db:reset")
      expect(c).to be_red
    end

    it "detects red tier for db:seed:replant" do
      c = described_class.new(command: "bin/rails db:seed:replant")
      expect(c).to be_red
    end

    it "detects yellow tier for db:rollback" do
      c = described_class.new(command: "bin/rails db:rollback")
      expect(c.tier).to eq(:yellow)
      expect(c).to be_yellow
    end

    it "detects yellow tier for db:migrate:down" do
      c = described_class.new(command: "bin/rails db:migrate:down VERSION=123")
      expect(c).to be_yellow
    end

    it "detects yellow tier for destroy" do
      c = described_class.new(command: "bin/rails destroy model User")
      expect(c).to be_yellow
    end

    it "detects yellow tier for bundle update (all gems)" do
      c = described_class.new(command: "bundle update")
      expect(c).to be_yellow
    end

    it "detects green tier for bundle update with specific gem" do
      c = described_class.new(command: "bundle update rails")
      expect(c).to be_green
    end

    it "detects green tier for db:migrate" do
      c = described_class.new(command: "bin/rails db:migrate")
      expect(c).to be_green
    end

    it "allows tier override" do
      c = described_class.new(command: "bin/rails db:migrate", tier: :yellow)
      expect(c).to be_yellow
    end
  end

  describe "#needs_confirmation?" do
    it "returns true for red tier" do
      c = described_class.new(command: "bin/rails db:drop")
      expect(c.needs_confirmation?).to be true
    end

    it "returns true for yellow tier" do
      c = described_class.new(command: "bin/rails db:rollback")
      expect(c.needs_confirmation?).to be true
    end

    it "returns false for green tier" do
      c = described_class.new(command: "bin/rails db:migrate")
      expect(c.needs_confirmation?).to be false
    end
  end

  describe "#prompt_text" do
    it "shows type prompt for red tier" do
      c = described_class.new(command: "bin/rails db:drop", required_text: "database")
      expect(c.prompt_text).to include("Type 'database' to confirm:")
    end

    it "shows y/n prompt for yellow tier" do
      c = described_class.new(command: "bin/rails db:rollback")
      expect(c.prompt_text).to include("Are you sure? (y/n):")
    end

    it "returns nil for green tier" do
      c = described_class.new(command: "bin/rails db:migrate")
      expect(c.prompt_text).to be_nil
    end
  end

  describe "#handle_key" do
    it "cancels on escape" do
      c = described_class.new(command: "bin/rails db:rollback")
      c.handle_key(:escape)
      expect(c).to be_cancelled
    end

    it "confirms yellow with y + enter" do
      c = described_class.new(command: "bin/rails db:rollback")
      c.handle_key("y")
      c.handle_key(:enter)
      expect(c).to be_confirmed
    end

    it "does not confirm yellow with n + enter" do
      c = described_class.new(command: "bin/rails db:rollback")
      c.handle_key("n")
      c.handle_key(:enter)
      expect(c).not_to be_confirmed
    end

    it "confirms red when required text matches" do
      c = described_class.new(command: "bin/rails db:drop", tier: :red, required_text: "database")
      "database".each_char { |ch| c.handle_key(ch) }
      c.handle_key(:enter)
      expect(c).to be_confirmed
    end

    it "does not confirm red when text does not match" do
      c = described_class.new(command: "bin/rails db:drop", tier: :red, required_text: "database")
      "wrong".each_char { |ch| c.handle_key(ch) }
      c.handle_key(:enter)
      expect(c).not_to be_confirmed
    end

    it "handles backspace" do
      c = described_class.new(command: "bin/rails db:rollback")
      c.handle_key("y")
      c.handle_key("n")
      c.handle_key(:backspace)
      c.handle_key(:enter)
      expect(c).to be_confirmed
    end

    it "ignores non-string keys for input" do
      c = described_class.new(command: "bin/rails db:rollback")
      c.handle_key(:tab)
      expect(c.input_text).to eq("")
    end
  end
end
