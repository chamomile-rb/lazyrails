# frozen_string_literal: true

module LazyRails
  # Panel-specific key handling, menus, and actions.
  # Included by App to keep the main file focused on lifecycle and routing.
  module PanelHandlers
    private

    # ─── Key handling per panel ────────────────────────────

    def handle_panel_key(msg)
      case current_panel.type
      when :server      then handle_server_key(msg)
      when :database    then handle_database_key(msg)
      when :tests       then handle_tests_key(msg)
      when :gems        then handle_gems_key(msg)
      when :routes      then handle_routes_key(msg)
      when :models      then handle_models_key(msg)
      when :rake        then nil
      when :console     then handle_console_key(msg)
      when :credentials then handle_credentials_key(msg)
      when :logs        then handle_logs_key(msg)
      when :mailers     then handle_mailers_key(msg)
      when :jobs        then handle_jobs_key(msg)
      when :custom      then handle_custom_key(msg)
      end
    end

    def handle_server_key(msg)
      case msg.key
      when "s"
        @server.start
        mode = @server.uses_bin_dev? ? "bin/dev" : "rails server"
        set_flash("Starting #{mode} on port #{@server.port}...")
      when "S"
        @server.stop
        set_flash("Server stopped.")
      when "r"
        @server.restart
        set_flash("Restarting server...")
      when "p"
        @input_mode.start_input(:change_port, prompt: "Port: ", placeholder: "3000")
      end
      nil
    end

    def handle_database_key(msg)
      case msg.key
      when "t"
        if @introspect_data
          @table_browser.show(@introspect_data.tables.keys)
        else
          set_flash("Data still loading...")
        end
      when "m"
        return run_rails_cmd("bin/rails db:migrate", :database)
      when "M"
        start_confirmation("bin/rails db:rollback", tier: :yellow)
      when "c"
        @input_mode.start_input(:migration_name, prompt: "Migration name: ", placeholder: "CreateUsers")
      when "d"
        migration = current_panel.selected_item
        start_confirmation("bin/rails db:migrate:down VERSION=#{migration.version}", tier: :yellow) if migration
      when "u"
        migration = current_panel.selected_item
        return run_rails_cmd("bin/rails db:migrate:up VERSION=#{migration.version}", :database) if migration
      when "s"
        start_confirmation("bin/rails db:seed", tier: :yellow)
      when "C"
        return run_rails_cmd("bin/rails db:create", :database)
      when "D"
        start_confirmation("bin/rails db:drop", tier: :red, required_text: "database")
      when "r"
        start_confirmation("bin/rails db:reset", tier: :red, required_text: "database")
      end
      nil
    end

    def handle_tests_key(msg)
      case msg.key
      when "a" then return run_rails_cmd(test_all_command, :tests)
      when "f" then return run_rails_cmd(test_failed_command, :tests)
      end
      nil
    end

    def handle_gems_key(msg)
      case msg.key
      when "u"
        gem_entry = current_panel.selected_item
        return run_rails_cmd(["bundle", "update", gem_entry.name], :gems) if gem_entry
      when "U"
        start_confirmation("bundle update", tier: :yellow)
      when "o"
        gem_entry = current_panel.selected_item
        return open_gem_homepage(gem_entry) if gem_entry
      end
      nil
    end

    def handle_routes_key(msg)
      toggle_route_grouping if msg.key == "g"
      nil
    end

    def handle_models_key(msg)
      @input_mode.start_input(:generate_model, prompt: "Model name: ", placeholder: "User name:string email:string") if msg.key == "g"
      nil
    end

    def handle_console_key(msg)
      case msg.key
      when "e"
        @input_mode.start_input(:eval_expression, prompt: "ruby> ", placeholder: "User.count")
      when "X"
        return exec("bin/rails", "console")
      end
      nil
    end

    def handle_credentials_key(msg)
      case msg.key
      when :enter
        return decrypt_selected_credential
      when :escape
        @credentials_content = nil
        update_detail_content
      when "e"
        return exec("bin/rails", "credentials:edit")
      end
      nil
    end

    def handle_logs_key(msg)
      panel = find_panel(:logs)
      return nil unless panel

      case msg.key
      when "s"
        @log_filter = @log_filter == :slow ? nil : :slow
        apply_log_filter(panel)
      when "e"
        @log_filter = @log_filter == :errors ? nil : :errors
        apply_log_filter(panel)
      when "c"
        @all_log_entries = []
        @log_filter = nil
        panel.finish_loading(items: [])
        @log_watcher&.clear
      end
      nil
    end

    def handle_mailers_key(msg)
      item = current_panel.selected_item
      return nil unless item

      if msg.key == "o"
        if @server.running?
          Platform.open_url("http://localhost:#{@server.port}/rails/mailers/#{item.mailer_class}/#{item.method_name}")
        else
          set_flash("Start the server first to open in browser")
        end
      end
      nil
    end

    def handle_jobs_key(msg)
      case msg.key
      when "r"
        item = current_panel.selected_item
        if item && item.status == "failed" && item.fe_id
          start_confirmation("Retry job ##{item.id}?", tier: :yellow)
          @pending_job_action = PendingJobAction.new(action: :retry, fe_id: item.fe_id)
        end
      when "d"
        item = current_panel.selected_item
        if item && item.status == "failed" && item.fe_id
          start_confirmation("Discard job ##{item.id}? This cannot be undone.", tier: :red)
          @pending_job_action = PendingJobAction.new(action: :discard, fe_id: item.fe_id)
        end
      when "A"
        unless current_panel.items.empty?
          start_confirmation("Retry ALL failed jobs?", tier: :yellow)
          @pending_job_action = PendingJobAction.new(action: :retry_all)
        end
      when "D"
        item = current_panel.selected_item
        if item && item.status == "scheduled"
          start_confirmation("Discard scheduled job ##{item.id}?", tier: :yellow)
          @pending_job_action = PendingJobAction.new(action: :discard_scheduled, job_id: item.id)
        end
      when "e"
        item = current_panel.selected_item
        if item && item.status == "scheduled"
          start_confirmation("Dispatch scheduled job ##{item.id} now?", tier: :green)
          @pending_job_action = PendingJobAction.new(action: :dispatch, job_id: item.id)
        end
      when "f"
        filters = %w[all ready claimed failed scheduled blocked finished]
        idx = filters.index(@jobs_filter) || 0
        @jobs_filter = filters[(idx + 1) % filters.size]
        set_flash("Jobs filter: #{@jobs_filter}")
        return load_jobs_cmd(@jobs_filter)
      end
      nil
    end

    def handle_custom_key(msg)
      item = current_panel.selected_item
      return nil unless item

      start_confirmation(item.command.split, tier: item.confirmation_tier) if msg.key == item.key
      nil
    end

    # ─── Enter key per panel ──────────────────────────────

    def handle_enter
      panel = current_panel
      item = panel.selected_item
      return nil unless item

      case panel.type
      when :tests
        return run_test_file_cmd(item)
      when :rake
        return start_confirmation(["bin/rails", item.name], tier: detect_rake_tier(item.name))
      when :credentials
        return decrypt_selected_credential
      when :mailers
        @mailer_preview_content = nil
        return render_mailer_preview_cmd(item)
      when :custom
        return start_confirmation(item.command.split, tier: item.confirmation_tier)
      end

      update_detail_content
      nil
    end

    # ─── Panel menus ──────────────────────────────────────

    def show_panel_menu
      items = panel_menu_items(current_panel)
      return if items.empty?

      @menu.show(title: current_panel.title, items: items)
    end

    def panel_menu_items(panel)
      case panel.type
      when :server
        server_menu_items
      when :database
        [
          menu_item("Run migrations", "m", :db_migrate),
          menu_item("Rollback migration", "M", :db_rollback),
          menu_item("Create migration", "c", :db_create_migration),
          menu_item("Browse tables", "t", :db_browse_tables),
          menu_item("Migrate down (selected)", "d", :db_migrate_down),
          menu_item("Migrate up (selected)", "u", :db_migrate_up),
          menu_item("Seed database", "s", :db_seed),
          menu_item("Create database", "C", :db_create),
          menu_item("Drop database", "D", :db_drop),
          menu_item("Reset database", "r", :db_reset)
        ]
      when :tests
        [
          menu_item("Run selected test", nil, :test_run_selected),
          menu_item("Run all tests", "a", :test_run_all),
          menu_item("Run failed tests", "f", :test_run_failed)
        ]
      when :gems
        [
          menu_item("Update selected gem", "u", :gem_update),
          menu_item("Update all gems", "U", :gem_update_all),
          menu_item("Open homepage", "o", :gem_open)
        ]
      when :routes
        [menu_item("Toggle grouping", "g", :routes_toggle_group)]
      when :models
        [menu_item("Generate model", "g", :model_generate)]
      when :console
        [
          menu_item("Evaluate expression", "e", :console_eval),
          menu_item("Open Rails console", "X", :console_open)
        ]
      when :credentials
        [
          menu_item("Decrypt and view", nil, :credentials_decrypt),
          menu_item("Edit credentials", "e", :credentials_edit)
        ]
      when :logs
        [
          menu_item("Filter slow requests", "s", :logs_filter_slow),
          menu_item("Filter errors", "e", :logs_filter_errors),
          menu_item("Clear logs", "c", :logs_clear)
        ]
      when :mailers
        [menu_item("Preview in browser", "o", :mailer_open)]
      when :jobs
        [
          menu_item("Retry failed job", "r", :jobs_retry),
          menu_item("Discard failed job", "d", :jobs_discard),
          menu_item("Retry all failed", "A", :jobs_retry_all),
          menu_item("Dispatch scheduled", "e", :jobs_dispatch),
          menu_item("Discard scheduled", "D", :jobs_discard_scheduled),
          menu_item("Cycle filter", "f", :jobs_filter),
          menu_item("Refresh", "R", :jobs_refresh)
        ]
      else
        []
      end
    end

    def handle_menu_action(action)
      case action
      when :server_start     then server_start_action
      when :server_stop      then server_stop_action
      when :server_restart   then server_restart_action
      when :server_port      then @input_mode.start_input(:change_port, prompt: "Port: ", placeholder: "3000")
      when :db_migrate       then return run_rails_cmd("bin/rails db:migrate", :database)
      when :db_rollback      then start_confirmation("bin/rails db:rollback", tier: :yellow)
      when :db_create_migration then @input_mode.start_input(:migration_name, prompt: "Migration name: ",
                                                                              placeholder: "CreateUsers")
      when :db_browse_tables then browse_tables_action
      when :db_migrate_down  then migrate_down_action
      when :db_migrate_up    then return migrate_up_action
      when :db_seed          then start_confirmation("bin/rails db:seed", tier: :yellow)
      when :db_create        then return run_rails_cmd("bin/rails db:create", :database)
      when :db_drop          then start_confirmation("bin/rails db:drop", tier: :red, required_text: "database")
      when :db_reset         then start_confirmation("bin/rails db:reset", tier: :red, required_text: "database")
      when :test_run_selected then return run_test_file_cmd(current_panel.selected_item) if current_panel.selected_item
      when :test_run_all     then return run_rails_cmd(test_all_command, :tests)
      when :test_run_failed  then return run_rails_cmd(test_failed_command, :tests)
      when :gem_update       then return gem_update_action
      when :gem_update_all   then start_confirmation("bundle update", tier: :yellow)
      when :gem_open         then return gem_open_action
      when :routes_toggle_group then toggle_route_grouping
      when :model_generate   then @input_mode.start_input(:generate_model, prompt: "Model name: ",
                                                                           placeholder: "User name:string email:string")
      when :console_eval     then @input_mode.start_input(:eval_expression, prompt: "ruby> ", placeholder: "User.count")
      when :console_open     then return exec("bin/rails", "console")
      when :credentials_decrypt then return decrypt_selected_credential
      when :credentials_edit then return exec("bin/rails", "credentials:edit")
      when :logs_filter_slow then toggle_log_filter(:slow)
      when :logs_filter_errors then toggle_log_filter(:errors)
      when :logs_clear       then clear_logs
      when :mailer_open      then open_mailer_preview
      when :jobs_retry       then jobs_retry_action
      when :jobs_discard     then jobs_discard_action
      when :jobs_retry_all   then jobs_retry_all_action
      when :jobs_dispatch    then jobs_dispatch_action
      when :jobs_discard_scheduled then jobs_discard_scheduled_action
      when :jobs_filter      then return cycle_jobs_filter
      when :jobs_refresh     then return load_jobs_cmd(@jobs_filter)
      else
        handle_generator_action(action)
      end

      nil
    end

    # ─── Input submission per panel ───────────────────────

    def handle_input_submit(value, purpose)
      case purpose
      when :filter
        current_panel.filter_text = value
        current_panel.reset_cursor
        nil
      when :migration_name
        run_rails_cmd(%w[bin/rails generate migration] + value.split, :database) unless value.empty?
      when :generate_model
        run_rails_cmd(%w[bin/rails generate model] + value.split, :models) unless value.empty?
      when :eval_expression
        run_eval_cmd(value) unless value.empty?
      when :table_where
        @table_browser.set_where(value)
        load_table_rows_cmd(@table_browser.selected_table) if @table_browser.selected_table
      when :table_order
        @table_browser.set_order(value)
        load_table_rows_cmd(@table_browser.selected_table) if @table_browser.selected_table
      when :change_port
        port = value.to_i
        if port.positive? && port < 65_536
          @server.port = port
          set_flash("Port changed to #{port}")
        else
          set_flash("Invalid port: #{value}")
        end
        nil
      else
        handle_generator_submit(value, purpose)
      end
    end

    # ─── Refresh per panel ────────────────────────────────

    def handle_refresh
      panel = current_panel
      case panel.type
      when :routes, :database, :models, :status, :rake
        panel.start_loading
        return load_introspect_cmd
      when :gems
        panel.start_loading
        return load_gems_cmd
      when :tests
        panel.start_loading
        return load_tests_cmd
      when :mailers
        panel.start_loading
        return load_mailers_cmd
      when :credentials
        discover_credentials
      when :custom
        @config = Config.load(@project.dir)
        custom_panel = find_panel(:custom)
        custom_panel&.finish_loading(items: @config.custom_commands)
      when :jobs
        return load_jobs_cmd(@jobs_filter)
      when :logs
        panel.finish_loading(items: [])
        @log_watcher.clear
        set_flash("Log buffer cleared.")
      end
      nil
    end

    # ─── Private helpers ──────────────────────────────────

    def menu_item(label, key, action)
      MenuOverlay::MenuItem.new(label: label, key: key, action: action)
    end

    def server_menu_items
      if @server.state == :running
        [
          menu_item("Stop server", "S", :server_stop),
          menu_item("Restart server", "r", :server_restart),
          menu_item("Change port", "p", :server_port)
        ]
      else
        [
          menu_item("Start server", "s", :server_start),
          menu_item("Change port", "p", :server_port)
        ]
      end
    end

    def server_start_action
      @server.start
      mode = @server.uses_bin_dev? ? "bin/dev" : "rails server"
      set_flash("Starting #{mode} on port #{@server.port}...")
    end

    def server_stop_action
      @server.stop
      set_flash("Server stopped.")
    end

    def server_restart_action
      @server.restart
      set_flash("Restarting server...")
    end

    def browse_tables_action
      if @introspect_data
        @table_browser.show(@introspect_data.tables.keys)
      else
        set_flash("Data still loading...")
      end
    end

    def migrate_down_action
      migration = current_panel.selected_item
      start_confirmation("bin/rails db:migrate:down VERSION=#{migration.version}", tier: :yellow) if migration
    end

    def migrate_up_action
      migration = current_panel.selected_item
      run_rails_cmd("bin/rails db:migrate:up VERSION=#{migration.version}", :database) if migration
    end

    def gem_update_action
      gem_entry = current_panel.selected_item
      run_rails_cmd(["bundle", "update", gem_entry.name], :gems) if gem_entry
    end

    def gem_open_action
      gem_entry = current_panel.selected_item
      open_gem_homepage(gem_entry) if gem_entry
    end

    def toggle_log_filter(kind)
      panel = find_panel(:logs)
      return unless panel

      @log_filter = @log_filter == kind ? nil : kind
      apply_log_filter(panel)
    end

    def clear_logs
      panel = find_panel(:logs)
      return unless panel

      @all_log_entries = []
      @log_filter = nil
      panel.finish_loading(items: [])
      @log_watcher&.clear
    end

    def open_mailer_preview
      item = current_panel.selected_item
      if item && @server.running?
        Platform.open_url("http://localhost:#{@server.port}/rails/mailers/#{item.mailer_class}/#{item.method_name}")
      else
        set_flash("Start the server first to open in browser")
      end
    end

    def jobs_retry_action
      item = current_panel.selected_item
      return unless item && item.status == "failed" && item.fe_id

      start_confirmation("Retry job ##{item.id}?", tier: :yellow)
      @pending_job_action = PendingJobAction.new(action: :retry, fe_id: item.fe_id)
    end

    def jobs_discard_action
      item = current_panel.selected_item
      return unless item && item.status == "failed" && item.fe_id

      start_confirmation("Discard job ##{item.id}? This cannot be undone.", tier: :red)
      @pending_job_action = PendingJobAction.new(action: :discard, fe_id: item.fe_id)
    end

    def jobs_retry_all_action
      return if current_panel.items.empty?

      start_confirmation("Retry ALL failed jobs?", tier: :yellow)
      @pending_job_action = PendingJobAction.new(action: :retry_all)
    end

    def jobs_dispatch_action
      item = current_panel.selected_item
      return unless item && item.status == "scheduled"

      start_confirmation("Dispatch scheduled job ##{item.id} now?", tier: :green)
      @pending_job_action = PendingJobAction.new(action: :dispatch, job_id: item.id)
    end

    def jobs_discard_scheduled_action
      item = current_panel.selected_item
      return unless item && item.status == "scheduled"

      start_confirmation("Discard scheduled job ##{item.id}?", tier: :yellow)
      @pending_job_action = PendingJobAction.new(action: :discard_scheduled, job_id: item.id)
    end

    def cycle_jobs_filter
      filters = %w[all ready claimed failed scheduled blocked finished]
      idx = filters.index(@jobs_filter) || 0
      @jobs_filter = filters[(idx + 1) % filters.size]
      set_flash("Jobs filter: #{@jobs_filter}")
      load_jobs_cmd(@jobs_filter)
    end

    def show_generator_menu
      items = App::GENERATOR_TYPES.map do |gt|
        menu_item(gt[:label], nil, :"generate_#{gt[:type]}")
      end
      @menu.show(title: "Generate", items: items)
    end

    def handle_generator_action(action)
      gen_match = action.to_s.match(/\Agenerate_(.+)\z/)
      return unless gen_match

      gen_type = gen_match[1]
      gt = App::GENERATOR_TYPES.find { |g| g[:type] == gen_type }
      return unless gt

      @input_mode.start_input(:"generate_#{gen_type}", prompt: "#{gt[:label]} args: ", placeholder: gt[:placeholder])
    end

    def handle_generator_submit(value, purpose)
      gen_match = purpose.to_s.match(/\Agenerate_(.+)\z/)
      return unless gen_match && !value.empty?

      gen_type = gen_match[1]
      run_rails_cmd(%W[bin/rails generate #{gen_type}] + value.split, :models)
    end
  end
end
