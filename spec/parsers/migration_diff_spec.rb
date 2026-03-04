# frozen_string_literal: true

RSpec.describe LazyRails::Parsers::MigrationDiff do
  describe ".parse" do
    it "parses add_column" do
      content = "add_column :users, :email, :string\n"
      diffs = described_class.parse(content)

      expect(diffs.size).to eq(1)
      expect(diffs[0].op).to eq(:add)
      expect(diffs[0].table).to eq("users")
      expect(diffs[0].column).to eq("email")
      expect(diffs[0].type).to eq("string")
    end

    it "parses add_column with extras" do
      content = "add_column :users, :age, :integer, null: false, default: 0\n"
      diffs = described_class.parse(content)

      expect(diffs[0].extras).to include("null: false")
      expect(diffs[0].extras).to include("default: 0")
    end

    it "parses remove_column" do
      content = "remove_column :users, :legacy_field\n"
      diffs = described_class.parse(content)

      expect(diffs.size).to eq(1)
      expect(diffs[0].op).to eq(:remove)
      expect(diffs[0].table).to eq("users")
      expect(diffs[0].column).to eq("legacy_field")
    end

    it "parses create_table" do
      content = "create_table :posts\n"
      diffs = described_class.parse(content)

      expect(diffs[0].op).to eq(:add)
      expect(diffs[0].table).to eq("posts")
      expect(diffs[0].type).to eq("TABLE")
    end

    it "parses drop_table" do
      content = "drop_table :old_posts\n"
      diffs = described_class.parse(content)

      expect(diffs[0].op).to eq(:remove)
      expect(diffs[0].table).to eq("old_posts")
      expect(diffs[0].type).to eq("TABLE")
    end

    it "parses add_index" do
      content = "add_index :users, [:email, :name]\n"
      diffs = described_class.parse(content)

      expect(diffs[0].op).to eq(:add)
      expect(diffs[0].type).to eq("INDEX")
      expect(diffs[0].extras).to include("[:email, :name]")
    end

    it "parses rename_column as remove + add" do
      content = "rename_column :users, :name, :full_name\n"
      diffs = described_class.parse(content)

      expect(diffs.size).to eq(2)
      expect(diffs[0].op).to eq(:remove)
      expect(diffs[0].column).to eq("name")
      expect(diffs[1].op).to eq(:add)
      expect(diffs[1].column).to eq("full_name")
      expect(diffs[1].extras).to eq("(renamed from name)")
    end

    it "parses t.type :column inside create_table blocks" do
      content = <<~MIGRATION
        create_table :users do |t|
          t.string :name
          t.integer :age
          t.timestamps
        end
      MIGRATION

      diffs = described_class.parse(content)
      columns = diffs.select(&:column)

      expect(columns.size).to eq(2)
      expect(columns[0].column).to eq("name")
      expect(columns[0].type).to eq("string")
      expect(columns[1].column).to eq("age")
      expect(columns[1].type).to eq("integer")
    end

    it "skips timestamps, index, and references in t.type lines" do
      content = <<~MIGRATION
        t.timestamps
        t.index :email
        t.references :user
      MIGRATION

      diffs = described_class.parse(content)
      expect(diffs).to be_empty
    end

    it "parses a full migration file" do
      content = <<~MIGRATION
        class CreatePosts < ActiveRecord::Migration[7.1]
          def change
            create_table :posts do |t|
              t.string :title
              t.text :body
              t.references :user
              t.timestamps
            end
            add_index :posts, :title
          end
        end
      MIGRATION

      diffs = described_class.parse(content)
      tables = diffs.select { |d| d.type == "TABLE" }
      columns = diffs.select { |d| d.column && d.op == :add }
      indexes = diffs.select { |d| d.type == "INDEX" }

      expect(tables.size).to eq(1)
      expect(columns.size).to eq(2) # title, body (references skipped)
      expect(indexes.size).to eq(1)
    end

    it "returns empty array for content with no schema changes" do
      content = "# just a comment\nputs 'hello'\n"
      expect(described_class.parse(content)).to be_empty
    end
  end

  describe LazyRails::Parsers::MigrationDiff::DiffLine do
    it "renders add lines with +" do
      line = described_class.new(op: :add, table: "users", column: "email", type: "string", extras: nil)
      expect(line.to_s).to include("+")
      expect(line.to_s).to include("email")
    end

    it "renders remove lines with -" do
      line = described_class.new(op: :remove, table: "users", column: "old_col", type: nil, extras: nil)
      expect(line.to_s).to include("-")
      expect(line.to_s).to include("old_col")
    end
  end
end
