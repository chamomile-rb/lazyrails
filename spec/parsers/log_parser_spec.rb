# frozen_string_literal: true

RSpec.describe LazyRails::Parsers::LogParser do
  describe ".parse" do
    it "parses a complete request block" do
      log = <<~LOG
        Started GET "/users" for 127.0.0.1 at 2024-01-15 10:00:00
        Processing by UsersController#index as HTML
          User Load (1.2ms)  SELECT "users".* FROM "users"
        Completed 200 OK in 15ms (Views: 10.0ms | ActiveRecord: 1.2ms)
      LOG

      entries = described_class.parse(log)
      expect(entries.size).to eq(1)

      entry = entries[0]
      expect(entry.verb).to eq("GET")
      expect(entry.path).to eq("/users")
      expect(entry.status).to eq("200")
      expect(entry.duration_ms).to eq(15)
    end

    it "extracts SQL queries" do
      log = <<~LOG
        Started GET "/posts" for 127.0.0.1 at 2024-01-15 10:00:00
          Post Load (2.5ms)  SELECT * FROM posts
          Comment Load (0.8ms)  SELECT * FROM comments
        Completed 200 OK in 20ms
      LOG

      entries = described_class.parse(log)
      expect(entries[0].sql_lines.size).to eq(2)
      expect(entries[0].sql_lines[0][:query]).to eq("Post Load")
      expect(entries[0].sql_lines[0][:duration_ms]).to eq(2.5)
      expect(entries[0].sql_lines[1][:query]).to eq("Comment Load")
    end

    it "parses multiple request blocks" do
      log = <<~LOG
        Started GET "/users" for 127.0.0.1 at 2024-01-15 10:00:00
        Completed 200 OK in 10ms

        Started POST "/users" for 127.0.0.1 at 2024-01-15 10:00:01
        Completed 302 Found in 5ms
      LOG

      entries = described_class.parse(log)
      expect(entries.size).to eq(2)
      expect(entries[0].verb).to eq("GET")
      expect(entries[1].verb).to eq("POST")
      expect(entries[1].status).to eq("302")
    end

    it "handles all HTTP verbs" do
      %w[GET POST PUT PATCH DELETE HEAD].each do |verb|
        log = "Started #{verb} \"/test\" for 127.0.0.1 at 2024-01-15\nCompleted 200 OK in 1ms\n"
        entries = described_class.parse(log)
        expect(entries.size).to eq(1)
        expect(entries[0].verb).to eq(verb)
      end
    end

    it "handles incomplete request blocks (no Completed line)" do
      log = <<~LOG
        Started GET "/slow" for 127.0.0.1 at 2024-01-15 10:00:00
        Processing by SlowController#index as HTML
      LOG

      entries = described_class.parse(log)
      expect(entries.size).to eq(1)
      expect(entries[0].status).to be_nil
      expect(entries[0].duration_ms).to be_nil
    end

    it "returns empty array for non-request log content" do
      log = "Rails 7.1.0 application starting\nSome random log line\n"
      expect(described_class.parse(log)).to be_empty
    end

    it "captures raw log text" do
      log = "Started GET \"/\" for 127.0.0.1 at 2024-01-15\nSome detail\nCompleted 200 OK in 1ms\n"
      entries = described_class.parse(log)
      expect(entries[0].raw).to include("Some detail")
    end

    it "detects CACHE and SQL query types" do
      log = <<~LOG
        Started GET "/cached" for 127.0.0.1 at 2024-01-15
          CACHE (0.0ms)  SELECT * FROM users
          SQL (0.3ms)  INSERT INTO logs
        Completed 200 OK in 5ms
      LOG

      sql = described_class.parse(log)[0].sql_lines
      expect(sql.size).to eq(2)
      expect(sql[0][:query]).to eq("CACHE")
      expect(sql[1][:query]).to eq("SQL")
    end
  end
end
