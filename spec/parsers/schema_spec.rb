# frozen_string_literal: true

RSpec.describe LazyRails::Parsers::Schema do
  describe ".parse" do
    it "returns empty hash for nil input" do
      expect(described_class.parse(nil)).to eq({})
    end

    it "returns empty hash for empty string" do
      expect(described_class.parse("")).to eq({})
    end

    it "parses a simple table with columns" do
      schema = <<~SCHEMA
        ActiveRecord::Schema[7.1].define(version: 2024_01_15_000000) do
          create_table "users", force: :cascade do |t|
            t.string "name"
            t.string "email"
            t.timestamps null: false
          end
        end
      SCHEMA

      tables = described_class.parse(schema)

      expect(tables).to have_key("users")
      cols = tables["users"]
      expect(cols.size).to eq(4) # name, email, created_at, updated_at

      name_col = cols.find { |c| c.name == "name" }
      expect(name_col.type).to eq(:string)
      expect(name_col.null).to be true
      expect(name_col.default).to be_nil
    end

    it "parses null: false constraint" do
      schema = <<~SCHEMA
        create_table "users" do |t|
          t.string "email", null: false
        end
      SCHEMA

      cols = described_class.parse(schema)["users"]
      expect(cols[0].null).to be false
    end

    it "parses default values" do
      schema = <<~SCHEMA
        create_table "settings" do |t|
          t.string "locale", default: "en"
          t.integer "retries", default: 3
          t.boolean "active", default: true
          t.float "rate", default: 1.5
          t.boolean "archived", default: false
        end
      SCHEMA

      cols = described_class.parse(schema)["settings"]

      expect(cols.find { |c| c.name == "locale" }.default).to eq("en")
      expect(cols.find { |c| c.name == "retries" }.default).to eq(3)
      expect(cols.find { |c| c.name == "active" }.default).to be true
      expect(cols.find { |c| c.name == "rate" }.default).to eq(1.5)
      expect(cols.find { |c| c.name == "archived" }.default).to be false
    end

    it "parses limit" do
      schema = <<~SCHEMA
        create_table "posts" do |t|
          t.string "title", limit: 255
        end
      SCHEMA

      col = described_class.parse(schema)["posts"][0]
      expect(col.limit).to eq(255)
    end

    it "parses references/belongs_to columns" do
      schema = <<~SCHEMA
        create_table "posts" do |t|
          t.references :user, null: false
          t.belongs_to :category
        end
      SCHEMA

      cols = described_class.parse(schema)["posts"]
      expect(cols.size).to eq(2)

      user_col = cols.find { |c| c.name == "user_id" }
      expect(user_col.type).to eq(:integer)
      expect(user_col.null).to be false

      cat_col = cols.find { |c| c.name == "category_id" }
      expect(cat_col.null).to be true
    end

    it "parses uuid references" do
      schema = <<~SCHEMA
        create_table "posts" do |t|
          t.references :user, type: :uuid
        end
      SCHEMA

      col = described_class.parse(schema)["posts"][0]
      expect(col.type).to eq(:uuid)
    end

    it "parses timestamps" do
      schema = <<~SCHEMA
        create_table "users" do |t|
          t.timestamps null: false
        end
      SCHEMA

      cols = described_class.parse(schema)["users"]
      expect(cols.size).to eq(2)
      expect(cols.map(&:name)).to eq(%w[created_at updated_at])
      expect(cols.map(&:type)).to eq(%i[datetime datetime])
    end

    it "parses multiple tables" do
      schema = <<~SCHEMA
        create_table "users" do |t|
          t.string "name"
        end

        create_table "posts" do |t|
          t.string "title"
          t.text "body"
        end
      SCHEMA

      tables = described_class.parse(schema)
      expect(tables.keys).to contain_exactly("users", "posts")
      expect(tables["posts"].size).to eq(2)
    end
  end
end
