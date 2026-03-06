# frozen_string_literal: true

RSpec.describe "Jobs structs and views" do
  describe LazyRails::JobEntry do
    let(:ready_job) do
      described_class.new(
        id: 1, class_name: "ProcessPaymentJob", queue_name: "default", status: "ready",
        arguments: '["arg1"]', priority: 0
      )
    end

    let(:failed_job) do
      described_class.new(
        id: 2, fe_id: 99, class_name: "SendEmailJob", queue_name: "mailers", status: "failed",
        arguments: '{"user_id":42}', priority: 5,
        error_class: "RuntimeError", error_message: "something broke",
        backtrace: ["app/jobs/send_email_job.rb:10", "activejob/base.rb:42"],
        failed_at: "2026-03-06T10:00:00Z"
      )
    end

    let(:scheduled_job) do
      described_class.new(
        id: 3, class_name: "CleanupJob", queue_name: "low", status: "scheduled",
        arguments: "[]", scheduled_at: "2026-03-06T12:00:00Z", priority: 10
      )
    end

    let(:claimed_job) do
      described_class.new(
        id: 4, class_name: "ImportJob", queue_name: "default", status: "claimed",
        arguments: "[]", worker_id: 7, started_at: "2026-03-06T09:00:00Z"
      )
    end

    let(:blocked_job) do
      described_class.new(
        id: 5, class_name: "UniqueJob", queue_name: "default", status: "blocked",
        arguments: "[]", concurrency_key: "unique-key-1", expires_at: "2026-03-06T13:00:00Z"
      )
    end

    let(:finished_job) do
      described_class.new(
        id: 6, class_name: "DoneJob", queue_name: "default", status: "finished",
        arguments: "[]", finished_at: "2026-03-06T11:00:00Z"
      )
    end

    it "defaults optional fields to nil" do
      expect(ready_job.fe_id).to be_nil
      expect(ready_job.error_class).to be_nil
      expect(ready_job.error_message).to be_nil
      expect(ready_job.scheduled_at).to be_nil
      expect(ready_job.created_at).to be_nil
      expect(ready_job.backtrace).to be_nil
      expect(ready_job.worker_id).to be_nil
      expect(ready_job.concurrency_key).to be_nil
    end

    it "renders class_name, queue, and status in to_s" do
      expect(ready_job.to_s).to include("ProcessPaymentJob")
      expect(ready_job.to_s).to include("default")
      expect(ready_job.to_s).to include("[ready]")
    end

    it "stores error info for failed jobs" do
      expect(failed_job.error_class).to eq("RuntimeError")
      expect(failed_job.error_message).to eq("something broke")
      expect(failed_job.fe_id).to eq(99)
      expect(failed_job.backtrace).to eq(["app/jobs/send_email_job.rb:10", "activejob/base.rb:42"])
      expect(failed_job.failed_at).to eq("2026-03-06T10:00:00Z")
    end

    it "stores scheduled_at for scheduled jobs" do
      expect(scheduled_job.scheduled_at).to eq("2026-03-06T12:00:00Z")
    end

    it "stores worker info for claimed jobs" do
      expect(claimed_job.worker_id).to eq(7)
      expect(claimed_job.started_at).to eq("2026-03-06T09:00:00Z")
    end

    it "stores concurrency info for blocked jobs" do
      expect(blocked_job.concurrency_key).to eq("unique-key-1")
      expect(blocked_job.expires_at).to eq("2026-03-06T13:00:00Z")
    end

    it "stores finished_at for finished jobs" do
      expect(finished_job.finished_at).to eq("2026-03-06T11:00:00Z")
    end
  end

  describe LazyRails::JobsLoadedMsg do
    it "represents unavailable state" do
      msg = described_class.new(available: false, jobs: [], counts: {}, error: nil)
      expect(msg.available).to be false
    end

    it "represents loaded jobs" do
      job = LazyRails::JobEntry.new(id: 1, class_name: "Foo", queue_name: "q", status: "ready", arguments: "[]")
      msg = described_class.new(available: true, jobs: [job], counts: { ready: 1 }, error: nil)
      expect(msg.jobs.size).to eq(1)
      expect(msg.counts[:ready]).to eq(1)
    end

    it "represents error state" do
      msg = described_class.new(available: true, jobs: [], counts: {}, error: "connection refused")
      expect(msg.error).to eq("connection refused")
    end
  end

  describe LazyRails::JobActionMsg do
    it "represents success" do
      msg = described_class.new(action: "retry", job_id: 5, success: true, error: nil)
      expect(msg.success).to be true
    end

    it "represents failure" do
      msg = described_class.new(action: "discard", job_id: 5, success: false, error: "not found")
      expect(msg.success).to be false
      expect(msg.error).to eq("not found")
    end

    it "supports retry_all action" do
      msg = described_class.new(action: "retry_all", job_id: nil, success: true, error: nil)
      expect(msg.action).to eq("retry_all")
      expect(msg.job_id).to be_nil
    end
  end

  describe LazyRails::Views::JobsView do
    let(:ready_job) do
      LazyRails::JobEntry.new(
        id: 1, class_name: "ProcessPaymentJob", queue_name: "default", status: "ready",
        arguments: '["arg1"]', priority: 0
      )
    end

    let(:failed_job) do
      LazyRails::JobEntry.new(
        id: 2, fe_id: 99, class_name: "SendEmailJob", queue_name: "mailers", status: "failed",
        arguments: '{"user_id":42}', priority: 5,
        error_class: "RuntimeError", error_message: "something broke",
        backtrace: ["app/jobs/send_email_job.rb:10", "activejob/base.rb:42"],
        failed_at: "2026-03-06T10:00:00Z"
      )
    end

    let(:finished_job) do
      LazyRails::JobEntry.new(
        id: 6, class_name: "DoneJob", queue_name: "default", status: "finished",
        arguments: "[]", finished_at: "2026-03-06T11:00:00Z"
      )
    end

    describe ".render_item" do
      it "renders ready job with circle icon" do
        output = described_class.render_item(ready_job, selected: false, width: 60)
        stripped = Flourish::ANSI.strip(output)
        expect(stripped).to include("\u25CB") # ○
        expect(stripped).to include("ProcessPaymentJob")
        expect(stripped).to include("default")
      end

      it "renders failed job with X icon" do
        output = described_class.render_item(failed_job, selected: false, width: 60)
        stripped = Flourish::ANSI.strip(output)
        expect(stripped).to include("\u2717") # ✗
        expect(stripped).to include("SendEmailJob")
      end

      it "renders finished job with check icon" do
        output = described_class.render_item(finished_job, selected: false, width: 60)
        stripped = Flourish::ANSI.strip(output)
        expect(stripped).to include("\u2713") # ✓
        expect(stripped).to include("DoneJob")
      end

      it "renders selected item with reverse style" do
        output = described_class.render_item(ready_job, selected: true, width: 60)
        expect(output).to include("\e[7m")
      end
    end

    describe ".render_detail" do
      it "renders job details with expanded fields" do
        output = described_class.render_detail(ready_job, width: 60)
        expect(output).to include("ProcessPaymentJob")
        expect(output).to include("ID:")
        expect(output).to include("Queue:")
        expect(output).to include("default")
        expect(output).to include("Status:")
        expect(output).to include("ready")
        expect(output).to include("Priority:")
      end

      it "renders arguments as pretty JSON" do
        output = described_class.render_detail(ready_job, width: 60)
        expect(output).to include("Arguments")
        expect(output).to include("arg1")
      end

      it "renders error info and backtrace for failed jobs" do
        output = described_class.render_detail(failed_job, width: 60)
        expect(output).to include("Error")
        expect(output).to include("RuntimeError")
        expect(output).to include("something broke")
        expect(output).to include("Backtrace")
        expect(output).to include("send_email_job.rb:10")
        expect(output).to include("Failed At:")
      end

      it "renders scheduled_at when present" do
        scheduled = LazyRails::JobEntry.new(
          id: 3, class_name: "CleanupJob", queue_name: "low", status: "scheduled",
          arguments: "[]", scheduled_at: "2026-03-06T12:00:00Z"
        )
        output = described_class.render_detail(scheduled, width: 60)
        expect(output).to include("Scheduled At:")
        expect(output).to include("2026-03-06T12:00:00Z")
      end

      it "renders worker info for claimed jobs" do
        claimed = LazyRails::JobEntry.new(
          id: 4, class_name: "ImportJob", queue_name: "default", status: "claimed",
          arguments: "[]", worker_id: 7, started_at: "2026-03-06T09:00:00Z"
        )
        output = described_class.render_detail(claimed, width: 60)
        expect(output).to include("Worker ID:")
        expect(output).to include("Started At:")
      end

      it "renders concurrency info for blocked jobs" do
        blocked = LazyRails::JobEntry.new(
          id: 5, class_name: "UniqueJob", queue_name: "default", status: "blocked",
          arguments: "[]", concurrency_key: "key-1", expires_at: "2026-03-06T13:00:00Z"
        )
        output = described_class.render_detail(blocked, width: 60)
        expect(output).to include("Concurrency:")
        expect(output).to include("key-1")
        expect(output).to include("Expires At:")
      end

      it "renders finished_at for finished jobs" do
        output = described_class.render_detail(finished_job, width: 60)
        expect(output).to include("Finished At:")
        expect(output).to include("2026-03-06T11:00:00Z")
      end

      it "does not show error section for non-failed jobs" do
        output = described_class.render_detail(ready_job, width: 60)
        stripped = Flourish::ANSI.strip(output)
        expect(stripped).not_to include("Error")
      end

      it "handles invalid JSON in arguments gracefully" do
        job = LazyRails::JobEntry.new(
          id: 1, class_name: "Foo", queue_name: "q", status: "ready",
          arguments: "not json"
        )
        output = described_class.render_detail(job, width: 60)
        expect(output).to include("not json")
      end

      it "handles hash/array arguments (not just strings)" do
        job = LazyRails::JobEntry.new(
          id: 1, class_name: "Foo", queue_name: "q", status: "ready",
          arguments: {"job_class" => "Foo", "arguments" => [1, 2]}
        )
        output = described_class.render_detail(job, width: 60)
        expect(output).to include("Arguments")
        expect(output).to include("Foo")
      end
    end
  end
end
