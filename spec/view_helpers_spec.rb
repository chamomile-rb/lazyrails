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
end
