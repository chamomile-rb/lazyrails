# frozen_string_literal: true

module LazyRails
  module Views
    module JobsView
      STATUS_ICONS = {
        "ready" => "\u25CB", # ○
        "claimed" => "\u25D1", # ◑
        "failed" => "\u2717", # ✗
        "scheduled" => "\u23F0", # ⏰
        "blocked" => "\u26D4", # ⛔
        "finished" => "\u2713" # ✓
      }.freeze

      STATUS_COLORS = {
        "ready" => "#04b575",
        "claimed" => "#e5c07b",
        "failed" => "#ff6347",
        "scheduled" => "#888888",
        "blocked" => "#888888",
        "finished" => "#666666"
      }.freeze

      def self.render_item(job, selected:, width:)
        icon = STATUS_ICONS.fetch(job.status, "?")
        text = "#{icon} #{job.class_name}  #{job.queue_name}"
        text = ViewHelpers.truncate(text, width)

        if selected
          ViewHelpers.selected_style.render(text.ljust(width))
        else
          color = STATUS_COLORS.fetch(job.status, "#cccccc")
          Flourish::Style.new.foreground(color).render(text)
        end
      end

      def self.render_detail(job, width:)
        lines = []
        lines << Flourish::Style.new.bold.render(job.class_name)
        lines << ""

        lines << "ID:           #{job.id}"
        lines << "Active Job:   #{job.active_job_id || 'n/a'}"
        lines << "Queue:        #{job.queue_name}"
        lines << "Status:       #{job.status}"
        lines << "Priority:     #{job.priority || 'n/a'}"
        lines << "Created:      #{job.created_at || 'n/a'}"

        case job.status
        when "scheduled"
          lines << "Scheduled At: #{job.scheduled_at || 'n/a'}"
        when "claimed"
          lines << "Worker ID:    #{job.worker_id || 'n/a'}"
          lines << "Started At:   #{job.started_at || 'n/a'}"
        when "finished"
          lines << "Finished At:  #{job.finished_at || 'n/a'}"
        when "blocked"
          lines << "Concurrency:  #{job.concurrency_key || 'n/a'}"
          lines << "Expires At:   #{job.expires_at || 'n/a'}"
        when "failed"
          lines << "Failed At:    #{job.failed_at || 'n/a'}"
        end

        # Arguments
        if job.arguments && !job.arguments.to_s.empty?
          lines << ""
          lines << Flourish::Style.new.bold.render("Arguments")
          begin
            parsed = job.arguments.is_a?(String) ? JSON.parse(job.arguments) : job.arguments
            lines << JSON.pretty_generate(parsed)
          rescue StandardError
            lines << job.arguments.to_s
          end
        end

        # Error details for failed jobs
        if job.status == "failed"
          lines << ""
          lines << Flourish::Style.new.foreground("#ff6347").bold.render("Error")
          lines << "#{job.error_class}: #{job.error_message}"

          if job.backtrace.is_a?(Array) && !job.backtrace.empty?
            lines << ""
            lines << Flourish::Style.new.bold.render("Backtrace")
            bt_style = Flourish::Style.new.foreground("#666666")
            job.backtrace.first(20).each do |bt_line|
              lines << bt_style.render("  #{bt_line}")
            end
          end
        end

        lines.join("\n")
      end
    end
  end
end
