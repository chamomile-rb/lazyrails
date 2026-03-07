# frozen_string_literal: true

RSpec.describe LazyRails::ViewHelpers do
  describe ".truncate" do
    it "returns the string unchanged when shorter than max" do
      expect(described_class.truncate("hello", 10)).to eq("hello")
    end

    it "returns the string unchanged when equal to max" do
      expect(described_class.truncate("hello", 5)).to eq("hello")
    end

    it "truncates with ellipsis when longer than max" do
      result = described_class.truncate("hello world", 8)
      expect(result).to eq("hello w\u2026")
      expect(result.length).to eq(8)
    end

    it "returns the string unchanged when max is less than 1" do
      expect(described_class.truncate("hello", 0)).to eq("hello")
      expect(described_class.truncate("hello", -1)).to eq("hello")
    end

    it "handles max of 2" do
      result = described_class.truncate("hello", 2)
      expect(result).to eq("h\u2026")
    end
  end

  describe ".classify_name" do
    it "converts underscored name to CamelCase" do
      expect(described_class.classify_name("user_accounts")).to eq("UserAccounts")
    end

    it "handles single word" do
      expect(described_class.classify_name("users")).to eq("Users")
    end

    it "handles multiple underscores" do
      expect(described_class.classify_name("admin_user_roles")).to eq("AdminUserRoles")
    end

    it "handles symbols via to_s" do
      expect(described_class.classify_name(:blog_posts)).to eq("BlogPosts")
    end
  end

  describe ".overlay" do
    let(:base) { (1..10).map { |i| "Base line #{i}".ljust(40) }.join("\n") }

    it "centers a small popup over the base layout" do
      popup = "╭──────╮\n│ Hi!! │\n╰──────╯"
      result = described_class.overlay(base, popup, 40, 10)
      lines = result.split("\n")

      # Base lines visible above and below the popup
      expect(Flourish::ANSI.strip(lines[0])).to include("Base line 1")
      expect(Flourish::ANSI.strip(lines[9])).to include("Base line 10")

      # Popup lines centered in the middle
      popup_rows = lines.select { |l| Flourish::ANSI.strip(l).include?("Hi!!") }
      expect(popup_rows.size).to eq(1)
    end

    it "preserves exact screen_height line count" do
      popup = "small"
      result = described_class.overlay(base, popup, 40, 10)
      expect(result.split("\n", -1).size).to eq(10)
    end

    it "handles popup taller than screen" do
      tall_popup = (1..20).map { |i| "popup #{i}" }.join("\n")
      result = described_class.overlay(base, tall_popup, 40, 5)
      lines = result.split("\n", -1)
      expect(lines.size).to eq(5)
    end

    it "handles empty popup gracefully" do
      result = described_class.overlay(base, "", 40, 10)
      expect(result).to include("Base line 1")
    end

    it "handles empty base" do
      result = described_class.overlay("", "popup", 40, 5)
      lines = result.split("\n", -1)
      expect(lines.size).to eq(5)
      expect(lines.any? { |l| l.include?("popup") }).to be true
    end

    it "handles popup wider than screen" do
      wide = "x" * 50
      result = described_class.overlay("base", wide, 20, 3)
      expect(result).to include("x" * 50)
    end

    it "works with ANSI-styled popup content" do
      styled = Flourish::Style.new.bold.render("Bold")
      result = described_class.overlay("aaa\nbbb\nccc", styled, 20, 3)
      expect(result).to include("\e[1m")
      expect(Flourish::ANSI.strip(result)).to include("Bold")
    end
  end
end
