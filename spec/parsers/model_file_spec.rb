# frozen_string_literal: true

RSpec.describe LazyRails::Parsers::ModelFile do
  describe ".parse" do
    it "returns empty arrays for nil input" do
      result = described_class.parse(nil)
      expect(result).to eq({ associations: [], validations: [] })
    end

    it "returns empty arrays for empty string" do
      result = described_class.parse("")
      expect(result).to eq({ associations: [], validations: [] })
    end

    it "parses has_many association" do
      content = <<~RUBY
        class User < ApplicationRecord
          has_many :posts
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:associations].size).to eq(1)
      expect(result[:associations][0].macro).to eq(:has_many)
      expect(result[:associations][0].name).to eq(:posts)
      expect(result[:associations][0].class_name).to eq("Posts")
    end

    it "parses has_one association" do
      content = <<~RUBY
        class User < ApplicationRecord
          has_one :profile
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:associations][0].macro).to eq(:has_one)
      expect(result[:associations][0].name).to eq(:profile)
    end

    it "parses belongs_to association" do
      content = <<~RUBY
        class Post < ApplicationRecord
          belongs_to :user
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:associations][0].macro).to eq(:belongs_to)
      expect(result[:associations][0].name).to eq(:user)
    end

    it "parses has_and_belongs_to_many" do
      content = <<~RUBY
        class Post < ApplicationRecord
          has_and_belongs_to_many :tags
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:associations][0].macro).to eq(:has_and_belongs_to_many)
    end

    it "uses explicit class_name when provided" do
      content = <<~RUBY
        class User < ApplicationRecord
          has_many :authored_posts, class_name: 'Post'
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:associations][0].class_name).to eq("Post")
    end

    it "infers class_name via classify when not provided" do
      content = <<~RUBY
        class User < ApplicationRecord
          has_many :blog_posts
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:associations][0].class_name).to eq("BlogPosts")
    end

    it "parses validates with presence" do
      content = <<~RUBY
        class User < ApplicationRecord
          validates :email, presence: true
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:validations].size).to eq(1)
      expect(result[:validations][0].kind).to eq(:presence)
      expect(result[:validations][0].attributes).to eq([:email])
    end

    it "parses validates with multiple validations" do
      content = <<~RUBY
        class User < ApplicationRecord
          validates :email, presence: true, uniqueness: true
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:validations].size).to eq(2)
      kinds = result[:validations].map(&:kind)
      expect(kinds).to contain_exactly(:presence, :uniqueness)
    end

    it "parses validates with multiple attributes" do
      content = <<~RUBY
        class User < ApplicationRecord
          validates :name, :email, presence: true
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:validations][0].attributes).to eq(%i[name email])
    end

    it "parses validates_presence_of" do
      content = <<~RUBY
        class User < ApplicationRecord
          validates_presence_of :email, :name
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:validations].size).to eq(1)
      expect(result[:validations][0].kind).to eq(:presence)
      expect(result[:validations][0].attributes).to eq(%i[email name])
    end

    it "skips comment lines" do
      content = <<~RUBY
        class User < ApplicationRecord
          # has_many :posts
          belongs_to :company
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:associations].size).to eq(1)
      expect(result[:associations][0].macro).to eq(:belongs_to)
    end

    it "parses both associations and validations" do
      content = <<~RUBY
        class User < ApplicationRecord
          has_many :posts
          belongs_to :company

          validates :email, presence: true, uniqueness: true
          validates :name, length: { maximum: 100 }
        end
      RUBY

      result = described_class.parse(content)
      expect(result[:associations].size).to eq(2)
      expect(result[:validations].size).to eq(3)
    end
  end
end
