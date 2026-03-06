# frozen_string_literal: true

RSpec.describe "New structs" do
  describe LazyRails::LogEntry do
    let(:entry) do
      described_class.new(
        verb: "GET", path: "/users", status: "200",
        duration_ms: 15, sql_lines: [], raw: ""
      )
    end

    it "renders verb, path, and status" do
      expect(entry.to_s).to include("GET")
      expect(entry.to_s).to include("/users")
      expect(entry.to_s).to include("200")
    end

    describe "#slow?" do
      it "returns false when no SQL queries are slow" do
        expect(entry).not_to be_slow
      end

      it "returns true when any SQL query exceeds 100ms" do
        slow = described_class.new(
          verb: "GET", path: "/", status: "200", duration_ms: 500,
          sql_lines: [{ query: "User Load", duration_ms: 150.0 }], raw: ""
        )
        expect(slow).to be_slow
      end

      it "uses float comparison for duration" do
        borderline = described_class.new(
          verb: "GET", path: "/", status: "200", duration_ms: 100,
          sql_lines: [{ query: "Load", duration_ms: 100.0 }], raw: ""
        )
        expect(borderline).not_to be_slow
      end
    end
  end

  describe LazyRails::RakeTask do
    it "renders name and description" do
      task = described_class.new(name: "db:migrate", description: "Run migrations", source: "Rails")
      expect(task.to_s).to include("db:migrate")
      expect(task.to_s).to include("Run migrations")
    end

    it "renders just name when description is empty" do
      task = described_class.new(name: "custom:task", description: "", source: nil)
      expect(task.to_s).to eq("custom:task")
    end
  end

  describe LazyRails::CredentialFile do
    it "renders environment when key exists" do
      cred = described_class.new(environment: "production", path: "/config/credentials/production.yml.enc", exists: true)
      expect(cred.to_s).to eq("production")
    end

    it "indicates missing key" do
      cred = described_class.new(environment: "staging", path: "/config/credentials/staging.yml.enc", exists: false)
      expect(cred.to_s).to eq("staging (missing key)")
    end
  end

  describe LazyRails::MailerPreview do
    let(:preview) do
      described_class.new(mailer_class: "UserMailer", method_name: "welcome", preview_path: "test/mailers/previews/user_mailer_preview.rb")
    end

    it "renders method name with indent" do
      expect(preview.to_s).to eq("  welcome")
    end

    it "renders display name with class and method" do
      expect(preview.display_name).to eq("UserMailer#welcome")
    end
  end

  describe LazyRails::CommandEntry do
    it "has optional annotation and undo_command" do
      entry = described_class.new(
        command: "bin/rails db:migrate", exit_code: 0, duration_ms: 500,
        timestamp: Time.now, stdout: "", stderr: ""
      )
      expect(entry.annotation).to be_nil
      expect(entry.undo_command).to be_nil
    end

    it "accepts annotation and undo_command" do
      entry = described_class.new(
        command: "bin/rails db:migrate", exit_code: 0, duration_ms: 500,
        timestamp: Time.now, stdout: "", stderr: "",
        annotation: "Applied: CreateUsers",
        undo_command: ["bin/rails", "db:rollback", "STEP=1"]
      )
      expect(entry.annotation).to eq("Applied: CreateUsers")
      expect(entry.undo_command).to eq(["bin/rails", "db:rollback", "STEP=1"])
    end

    it "renders with check mark for success" do
      entry = described_class.new(
        command: "db:migrate", exit_code: 0, duration_ms: 1000,
        timestamp: Time.now, stdout: "", stderr: ""
      )
      expect(entry.to_s).to include("\u2713")
    end

    it "renders with X for failure" do
      entry = described_class.new(
        command: "db:migrate", exit_code: 1, duration_ms: 1000,
        timestamp: Time.now, stdout: "", stderr: ""
      )
      expect(entry.to_s).to include("\u2717")
    end
  end

  describe LazyRails::TableRowsLoadedMsg do
    it "includes total field" do
      msg = described_class.new(table: "users", columns: ["id"], rows: [["1"]], total: 42, error: nil)
      expect(msg.total).to eq(42)
    end

    it "includes error field" do
      msg = described_class.new(table: "users", columns: [], rows: [], total: 0, error: "bad SQL")
      expect(msg.error).to eq("bad SQL")
    end
  end
end
