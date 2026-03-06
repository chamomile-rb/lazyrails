# frozen_string_literal: true

module LazyRails
  # Handlers for async messages (loaded data, finished commands, etc.).
  # Included by App to keep the main file focused on lifecycle and routing.
  module MessageHandlers
    private

    def handle_tick
      @flash.tick

      # Detect server state changes
      current_state = @server.state
      if current_state != @last_server_state
        case current_state
        when :running then set_flash("Server running on port #{@server.port}")
        when :stopped then set_flash("Server stopped.") if @last_server_state == :running
        when :error   then set_flash("Server error — check detail pane")
        end
        @last_server_state = current_state
        update_detail_content if current_panel.type == :server
      elsif current_panel.type == :server && @server.log_changed?
        update_detail_content
      end

      # Auto-refresh jobs panel when focused (every 5 ticks = 5 seconds)
      if current_panel.type == :jobs && @jobs_available != false
        @jobs_tick_counter += 1
        if @jobs_tick_counter >= 5
          @jobs_tick_counter = 0
          return batch(load_jobs_cmd(@jobs_filter), ui_tick)
        end
      else
        @jobs_tick_counter = 0
      end

      # Check log watcher for new entries
      if @log_watcher.changed?
        new_entries = @log_watcher.take_entries
        unless new_entries.empty?
          @all_log_entries = (@all_log_entries + new_entries).last(1000)
          panel = find_panel(:logs)
          if panel
            apply_log_filter(panel)
            update_detail_content if current_panel.type == :logs
          end
        end
      end

      ui_tick
    end

    def handle_introspect_loaded(msg)
      @file_cache.invalidate

      if msg.error
        load_fallback_data
        [:routes, :database, :models, :rake].each { |t| find_panel(t).fail_loading(msg.error) }
        find_panel(:status).fail_loading(msg.error)
      else
        @introspect_data = msg.data

        find_panel(:routes).finish_loading(items: msg.data.routes)

        db_panel = find_panel(:database)
        db_panel.finish_loading(items: msg.data.migrations)
        pending = Views::DatabaseView.pending_count(msg.data.migrations)
        db_panel.update_title(pending > 0 ? "Database (#{pending} pending)" : "Database")

        find_panel(:models).finish_loading(items: msg.data.models)
        find_panel(:rake).finish_loading(items: msg.data.rake_tasks)

        @about_data = msg.data.about || {}
        @stats_data = msg.data.stats || {}
        @notes_data = msg.data.notes || []
        find_panel(:status).fail_loading(nil)
      end

      update_detail_content
      nil
    end

    def handle_gems_loaded(msg)
      find_panel(:gems).finish_loading(items: msg.gems, error: msg.error)
      update_detail_content
    end

    def handle_tests_loaded(msg)
      find_panel(:tests).finish_loading(items: msg.files, error: msg.error)
      update_detail_content
    end

    def handle_command_finished(msg)
      @command_log.add(msg.entry)
      set_flash("#{msg.entry.success? ? "\u2713" : "\u2717"} #{msg.entry.command} (#{msg.entry.duration_ms}ms)")

      case msg.panel
      when :database, :models then return load_introspect_cmd
      when :gems              then return load_gems_cmd
      when :tests             then return load_tests_cmd
      end

      nil
    end

    def handle_test_finished(msg)
      tests_panel = find_panel(:tests)
      idx = tests_panel.items.index { |f| f.path == msg.path }
      if idx
        tests_panel.replace_item_at(idx, TestFile.new(
          path: msg.path,
          status: msg.status,
          last_output: msg.output
        ))
      end
      set_flash("#{msg.status == :passed ? "\u2713" : "\u2717"} #{msg.path}")
      update_detail_content
    end

    def handle_table_rows_loaded(msg)
      return unless @table_browser.visible? && @table_browser.screen == :row_data
      return unless msg.table == @table_browser.selected_table

      if msg.error
        @table_browser.fail_loading(msg.error)
      else
        @table_browser.load_rows(msg.columns, msg.rows, total: msg.total)
      end
    end

    def handle_eval_finished(msg)
      panel = find_panel(:console)
      @eval_history.unshift(msg.entry)
      @eval_history = @eval_history.first(50)
      panel.finish_loading(items: @eval_history)
      update_detail_content
    end

    def handle_credentials_loaded(msg)
      if msg.content
        @credentials_content = msg.content
      elsif msg.error
        @credentials_content = "Error: #{msg.error}"
      end
      update_detail_content
    end

    def handle_mailers_loaded(msg)
      panel = find_panel(:mailers)
      panel&.finish_loading(items: msg.previews, error: msg.error)
      update_detail_content
    end

    def handle_jobs_loaded(msg)
      panel = find_panel(:jobs)
      return unless panel

      @jobs_available = msg.available

      if !msg.available
        panel.finish_loading(items: [])
        panel.update_title("Jobs (N/A)")
      elsif msg.error
        panel.fail_loading(msg.error)
      else
        panel.finish_loading(items: msg.jobs)
        counts = msg.counts
        failed = counts[:failed] || 0
        total = counts.values.sum
        title = if failed > 0
          "Jobs (#{failed} failed)"
        elsif total > 0
          "Jobs (#{total})"
        else
          "Jobs"
        end
        panel.update_title(title)
      end
      update_detail_content
    end

    def handle_job_action(msg)
      if msg.success
        set_flash("\u2713 #{msg.action} job ##{msg.job_id}")
      else
        set_flash("\u2717 #{msg.action} failed: #{msg.error}")
      end
      load_jobs_cmd(@jobs_filter)
    end

    def handle_mailer_preview_loaded(msg)
      if msg.error
        @mailer_preview_content = { error: msg.error }
      else
        @mailer_preview_content = {
          subject: msg.subject, to: msg.to, from: msg.from, body: msg.body
        }
      end
      update_detail_content
    end

    def handle_resize(msg)
      @width = msg.width
      @height = msg.height
      right_width = @width - (@width * LEFT_WIDTH_RATIO).to_i - 1
      @detail_viewport.set_width(right_width - 4)
      @detail_viewport.set_height(@height - 4)
      update_detail_content
    end
  end
end
