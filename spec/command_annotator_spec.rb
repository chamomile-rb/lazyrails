# frozen_string_literal: true

RSpec.describe LazyRails::CommandAnnotator do
  describe ".annotate" do
    it "returns annotation and undo as a pair" do
      annotation, undo = described_class.annotate("bin/rails db:migrate", "== CreateUsers: migrating\n", "", 0)
      expect(annotation).to eq("Applied: CreateUsers")
      expect(undo).to eq(["bin/rails", "db:rollback", "STEP=1"])
    end

    it "returns nils for unrecognized commands" do
      annotation, undo = described_class.annotate("bin/rails server", "", "", 0)
      expect(annotation).to be_nil
      expect(undo).to be_nil
    end
  end

  describe "migration annotations" do
    it "annotates successful db:migrate with applied migration names" do
      stdout = <<~OUT
        == CreateUsers: migrating ========================
        == CreateUsers: migrated (0.005s) ================
        == AddEmailToUsers: migrating ====================
        == AddEmailToUsers: migrated (0.003s) ============
      OUT

      annotation, _ = described_class.annotate("bin/rails db:migrate", stdout, "", 0)
      expect(annotation).to eq("Applied: CreateUsers, AddEmailToUsers")
    end

    it "annotates db:migrate with no pending migrations" do
      annotation, _ = described_class.annotate("bin/rails db:migrate", "", "", 0)
      expect(annotation).to eq("No pending migrations")
    end

    it "does not annotate db:migrate:down as a full migrate" do
      annotation, _ = described_class.annotate("bin/rails db:migrate:down VERSION=123", "", "", 0)
      expect(annotation).to be_nil
    end
  end

  describe "rollback annotations" do
    it "annotates successful db:rollback with reverted migration names" do
      stdout = "== CreateUsers: reverting ========================\n"
      annotation, _ = described_class.annotate("bin/rails db:rollback", stdout, "", 0)
      expect(annotation).to eq("Reverted: CreateUsers")
    end

    it "annotates rollback with no output" do
      annotation, _ = described_class.annotate("bin/rails db:rollback", "", "", 0)
      expect(annotation).to eq("Rolled back")
    end
  end

  describe "generate annotations" do
    it "annotates generate model with created files" do
      stdout = <<~OUT
        create  db/migrate/20240115_create_users.rb
        create  app/models/user.rb
        create  test/models/user_test.rb
      OUT

      annotation, _ = described_class.annotate("bin/rails generate model User", stdout, "", 0)
      expect(annotation).to include("db/migrate/20240115_create_users.rb")
      expect(annotation).to include("app/models/user.rb")
    end

    it "annotates generate migration with created files" do
      stdout = "  create  db/migrate/20240115_add_email.rb\n"
      annotation, _ = described_class.annotate("bin/rails generate migration AddEmail", stdout, "", 0)
      expect(annotation).to eq("Created: db/migrate/20240115_add_email.rb")
    end
  end

  describe "destroy annotations" do
    it "annotates destroy model with removed files" do
      stdout = <<~OUT
        remove  db/migrate/20240115_create_users.rb
        remove  app/models/user.rb
      OUT

      annotation, _ = described_class.annotate("bin/rails destroy model User", stdout, "", 0)
      expect(annotation).to include("Removed:")
      expect(annotation).to include("app/models/user.rb")
    end
  end

  describe "error annotations" do
    it "annotates failed commands with first error line" do
      annotation, _ = described_class.annotate("bin/rails db:migrate", "", "StandardError: something broke\nbacktrace...", 1)
      expect(annotation).to eq("Failed: StandardError: something broke")
    end

    it "returns nil for empty stderr on failure" do
      annotation, _ = described_class.annotate("bin/rails db:migrate", "", "", 1)
      expect(annotation).to be_nil
    end
  end

  describe "undo commands" do
    it "returns rollback for successful db:migrate" do
      stdout = "== CreateUsers: migrating\n== AddPosts: migrating\n"
      _, undo = described_class.annotate("bin/rails db:migrate", stdout, "", 0)
      expect(undo).to eq(["bin/rails", "db:rollback", "STEP=2"])
    end

    it "returns nil undo for failed db:migrate" do
      _, undo = described_class.annotate("bin/rails db:migrate", "", "error", 1)
      expect(undo).to be_nil
    end

    it "returns destroy for successful generate model" do
      _, undo = described_class.annotate("bin/rails generate model User", "create app/models/user.rb", "", 0)
      expect(undo).to eq(["bin/rails", "destroy", "model", "User"])
    end

    it "returns db:migrate for successful rollback" do
      _, undo = described_class.annotate("bin/rails db:rollback", "== CreateUsers: reverting", "", 0)
      expect(undo).to eq(["bin/rails", "db:migrate"])
    end

    it "returns nil undo when no migrations applied" do
      _, undo = described_class.annotate("bin/rails db:migrate", "", "", 0)
      expect(undo).to be_nil
    end
  end
end
