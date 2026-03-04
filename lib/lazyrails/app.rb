# frozen_string_literal: true

module LazyRails
  # Custom messages for async operations
  TestFinishedMsg = Data.define(:path, :status, :output)

  class App
    include Chamomile::Model
    include Chamomile::Commands
    include Renderer
    include DataLoader

    PANEL_DEFS = [
      { type: :status,   title: "Status" },
      { type: :server,   title: "Server" },
      { type: :routes,   title: "Routes" },
      { type: :database, title: "Database" },
      { type: :models,   title: "Models" },
      { type: :tests,    title: "Tests" },
      { type: :gems,     title: "Gems" },
      { type: :rake,     title: "Rake" },
      { type: :console,  title: "Console" },
      { type: :credentials, title: "Credentials" },
      { type: :logs,     title: "Logs" },
      { type: :mailers,  title: "Mailers" }
    ].freeze

    FOCUSED_COLOR = "#7d56f4"
    UNFOCUSED_COLOR = "#444444"
    LEFT_WIDTH_RATIO = 0.30
    UI_TICK_SECONDS = 1.0

    def initialize(project)
      @project = project
      @config = Config.load(project.dir)
      @panels = PANEL_DEFS.map { |d| Panel.new(type: d[:type], title: d[:title]) }

      unless @config.empty?
        @panels << Panel.new(type: :custom, title: "Custom")
      end

      @focused_panel = 0
      @width = 80
      @height = 24
      @command_log = CommandLog.new
      @server = ServerManager.new(project)
      @log_watcher = LogWatcher.new(project)
      @detail_viewport = Petals::Viewport.new(width: 40, height: 20)

      # Component objects
      @flash = Flash.new
      @command_log_overlay = CommandLogOverlay.new(@command_log)
      @table_browser = TableBrowser.new
      @input_mode = InputMode.new

      # Data stores
      @introspect_data = nil
      @about_data = {}
      @stats_data = {}
      @notes_data = []
      @eval_history = []
      @credentials_content = nil
      @mailer_preview_content = nil
      @all_log_entries = []
      @log_filter = nil

      # UI state
      @show_help = false
      @confirmation = nil
      @route_grouped = false
      @last_server_state = :stopped

      # Caches
      @detail_content = ""
      @file_cache = FileCache.new
      @panel_render_cache = {}
    end

    # ─── Chamomile lifecycle ──────────────────────────────

    def start
      unless @config.empty?
        custom_panel = find_panel(:custom)
        custom_panel.finish_loading(items: @config.custom_commands) if custom_panel
      end

      # Discover credential files (no subprocess needed)
      discover_credentials

      # Start log watcher background thread
      @log_watcher.start

      batch(
        load_introspect_cmd,
        load_gems_cmd,
        load_tests_cmd,
        load_mailers_cmd,
        ui_tick
      )
    end

    def update(msg)
      # Handle confirmation mode first
      return handle_confirmation(msg) if @confirmation

      # Handle input mode (filter / prompts)
      return handle_input_mode(msg) if @input_mode.active?

      case msg
      when Chamomile::WindowSizeMsg
        handle_resize(msg)
      when Chamomile::KeyMsg
        return handle_key(msg)
      when Chamomile::TickMsg
        return handle_tick
      when Chamomile::InterruptMsg
        return shutdown
      when IntrospectLoadedMsg
        return handle_introspect_loaded(msg)
      when GemsLoadedMsg
        handle_gems_loaded(msg)
      when TestsLoadedMsg
        handle_tests_loaded(msg)
      when CommandFinishedMsg
        return handle_command_finished(msg)
      when TestFinishedMsg
        handle_test_finished(msg)
      when TableRowsLoadedMsg
        handle_table_rows_loaded(msg)
      when EvalFinishedMsg
        handle_eval_finished(msg)
      when CredentialsLoadedMsg
        handle_credentials_loaded(msg)
      when MailersLoadedMsg
        handle_mailers_loaded(msg)
      when MailerPreviewLoadedMsg
        handle_mailer_preview_loaded(msg)
      end

      nil
    end

    def view
      return render_help if @show_help
      return @command_log_overlay.render(width: @width) if @command_log_overlay.visible?
      return @table_browser.render(width: @width, height: @height) if @table_browser.visible?

      left_width = (@width * LEFT_WIDTH_RATIO).to_i
      right_width = @width - left_width - 1

      left_content = render_left_panels(left_width)
      right_content = render_right_pane(right_width)

      layout = Flourish.join_horizontal(Flourish::TOP, left_content, " ", right_content)

      if @confirmation
        layout = "#{layout}\n#{render_confirmation}"
      elsif @input_mode.active?
        layout = "#{layout}\n#{render_filter_bar}"
      else
        layout = "#{layout}\n#{render_status_bar}"
      end

      layout
    end

    private

    # ─── Helpers ──────────────────────────────────────────

    def ui_tick
      tick(UI_TICK_SECONDS)
    end

    def current_panel
      @panels[@focused_panel]
    end

    def find_panel(type)
      @panels.find { |p| p.type == type }
    end

    def panel_visible_height
      heights = distribute_panel_heights(@height - 2)
      h = heights[@focused_panel] || 5
      [h - 2, 1].max
    end

    def detail_width
      [@width - (@width * LEFT_WIDTH_RATIO).to_i - 5, 10].max
    end

    def distribute_panel_heights(total)
      n = @panels.size
      min_unfocused = 3

      unfocused_total = (n - 1) * min_unfocused
      focused_height = total - unfocused_total

      # Fall back to equal distribution if terminal is too small
      if focused_height < min_unfocused
        base = total / n
        remainder = total % n
        return @panels.each_with_index.map { |_, i| i < remainder ? base + 1 : base }
      end

      @panels.each_with_index.map { |_, i| i == @focused_panel ? focused_height : min_unfocused }
    end

    def set_flash(message, duration: 3)
      @flash.set(message, duration: duration)
    end

    def shutdown
      @server.stop
      @log_watcher.stop
      quit
    end

    def clear_panel_state
      @credentials_content = nil if current_panel.type == :credentials
      @mailer_preview_content = nil if current_panel.type == :mailers
      @pending_credential = nil
    end

    def test_all_command
      if File.directory?(File.join(@project.dir, "spec"))
        "bundle exec rspec"
      else
        "bin/rails test"
      end
    end

    def test_failed_command
      if File.directory?(File.join(@project.dir, "spec"))
        "bundle exec rspec --only-failures"
      else
        "bin/rails test --fail-fast"
      end
    end

    def toggle_route_grouping
      panel = find_panel(:routes)
      return unless @introspect_data

      items = if @route_grouped
        @route_grouped = false
        @introspect_data.routes
      else
        @route_grouped = true
        @introspect_data.routes.sort_by do |r|
          r.action.split("#").first rescue "zzz"
        end
      end
      panel.finish_loading(items: items)
      panel.reset_cursor
    end

    # ─── Key handling (from KeyHandler) ───────────────────

    def handle_key(msg)
      # Help overlay intercepts all keys
      if @show_help
        @show_help = false if msg.key == "?" || msg.key == :escape
        return msg.key == "q" ? shutdown : nil
      end

      # Command log overlay intercepts all keys
      if @command_log_overlay.visible?
        signal = @command_log_overlay.handle_key(msg.key)
        return shutdown if signal == :quit
        return nil
      end

      # Table browser overlay intercepts all keys
      if @table_browser.visible?
        signal = @table_browser.handle_key(msg.key)
        case signal
        when :quit  then return shutdown
        when :close then @table_browser.hide
        when Hash
          return load_table_rows_cmd(signal[:table]) if signal[:action] == :load_table
        end
        return nil
      end

      # Handle Shift+Tab (Chamomile sends :tab with [:shift] modifier)
      if msg.key == :tab && msg.shift?
        clear_panel_state
        @focused_panel = (@focused_panel - 1) % @panels.size
        update_detail_content
        return nil
      end

      case msg.key
      when "q"
        return shutdown
      when "?"
        @show_help = true
      when "L"
        @command_log_overlay.show
      when :tab
        clear_panel_state
        @focused_panel = (@focused_panel + 1) % @panels.size
        update_detail_content
      when "1".."9"
        idx = msg.key.to_i - 1
        if idx < @panels.size
          @focused_panel = idx
          update_detail_content
        end
      when "j", :down
        current_panel.move_cursor(1, panel_visible_height)
        update_detail_content
      when "k", :up
        current_panel.move_cursor(-1, panel_visible_height)
        update_detail_content
      when :enter
        return handle_enter
      when "/"
        start_filter
      when "R"
        return handle_refresh
      when "z"
        return handle_undo
      else
        return handle_panel_key(msg)
      end

      nil
    end

    def handle_panel_key(msg)
      case current_panel.type
      when :server   then handle_server_key(msg)
      when :database then handle_database_key(msg)
      when :tests    then handle_tests_key(msg)
      when :gems     then handle_gems_key(msg)
      when :routes   then handle_routes_key(msg)
      when :models   then handle_models_key(msg)
      when :rake     then handle_rake_key(msg)
      when :console  then handle_console_key(msg)
      when :credentials then handle_credentials_key(msg)
      when :logs     then handle_logs_key(msg)
      when :mailers  then handle_mailers_key(msg)
      when :custom   then handle_custom_key(msg)
      end
    end

    def handle_server_key(msg)
      case msg.key
      when "s"
        @server.start
        set_flash("Starting server on port #{@server.port}...")
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
        if migration
          start_confirmation("bin/rails db:migrate:down VERSION=#{migration.version}", tier: :yellow)
        end
      when "u"
        migration = current_panel.selected_item
        return run_rails_cmd("bin/rails db:migrate:up VERSION=#{migration.version}", :database) if migration
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
      case msg.key
      when "g"
        toggle_route_grouping
      end
      nil
    end

    def handle_models_key(msg)
      case msg.key
      when "g"
        @input_mode.start_input(:generate_model, prompt: "Model name: ", placeholder: "User name:string email:string")
      end
      nil
    end

    def handle_rake_key(_msg) = nil

    def detect_rake_tier(name)
      return :red    if name.include?("drop") || name.include?("purge")
      return :yellow if name.include?("seed") || name.include?("reset")
      :green
    end

    def decrypt_selected_credential
      item = current_panel.selected_item
      return nil unless item

      if item.exists
        env = item.environment.gsub(" (default)", "")
        start_confirmation("bin/rails credentials:show --environment #{env}", tier: :yellow)
        @pending_credential = item
      else
        set_flash("Key file missing for #{item.environment}")
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

    def apply_log_filter(panel)
      entries = @all_log_entries || []
      filtered = case @log_filter
      when :slow   then entries.select(&:slow?)
      when :errors then entries.select { |e| e.status.to_i >= 400 }
      else entries
      end
      panel.finish_loading(items: filtered)
    end

    def handle_mailers_key(msg)
      item = current_panel.selected_item
      return nil unless item

      # Enter is handled by handle_enter
      case msg.key
      when "o"
        if @server.running?
          Platform.open_url("http://localhost:#{@server.port}/rails/mailers/#{item.mailer_class}/#{item.method_name}")
        else
          set_flash("Start the server first to open in browser")
        end
      end
      nil
    end

    def handle_console_key(msg)
      case msg.key
      when "e"
        @input_mode.start_input(:eval_expression,
          prompt: "ruby> ",
          placeholder: "User.count")
      when "X"
        return exec("bin/rails", "console")
      end
      nil
    end

    def handle_custom_key(msg)
      item = current_panel.selected_item
      return nil unless item

      if msg.key == item.key
        start_confirmation(item.command.split, tier: item.confirmation_tier)
      end
      nil
    end

    def handle_enter
      panel = current_panel
      item = panel.selected_item
      return nil unless item

      case panel.type
      when :tests
        return run_test_file_cmd(item)
      when :rake
        return start_confirmation(
          ["bin/rails", item.name],
          tier: detect_rake_tier(item.name)
        )
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

    # ─── Input mode (from InputHandler) ───────────────────

    def start_filter
      return unless %i[routes models tests gems rake console logs mailers custom].include?(current_panel.type)

      @input_mode.start_filter
    end

    def handle_input_mode(msg)
      return nil unless msg.is_a?(Chamomile::KeyMsg)

      signal = @input_mode.handle_key(msg)

      case signal
      when :cancelled
        @input_mode.deactivate
        current_panel.filter_text = ""
        current_panel.reset_cursor
      when Hash
        case signal[:action]
        when :submitted
          value = signal[:value]
          purpose = signal[:purpose]
          @input_mode.deactivate
          return handle_input_submit(value, purpose)
        when :changed
          current_panel.filter_text = signal[:value]
          current_panel.reset_cursor
        end
      end

      nil
    end

    def handle_input_submit(value, purpose)
      case purpose
      when :filter
        current_panel.filter_text = value
        current_panel.reset_cursor
        nil
      when :migration_name
        return run_rails_cmd(%w[bin/rails generate migration] + value.split, :database) unless value.empty?
      when :generate_model
        return run_rails_cmd(%w[bin/rails generate model] + value.split, :models) unless value.empty?
      when :eval_expression
        return run_eval_cmd(value) unless value.empty?
      when :change_port
        port = value.to_i
        if port > 0 && port < 65_536
          @server.port = port
          set_flash("Port changed to #{port}")
        else
          set_flash("Invalid port: #{value}")
        end
        nil
      end
    end

    def start_confirmation(command, tier: nil, required_text: nil)
      tier ||= Confirmation.detect_tier(command)

      # Green-tier commands skip confirmation — run immediately
      return run_rails_cmd(command, current_panel.type) if tier == :green

      required_text ||= current_panel.title.downcase if tier == :red
      @confirmation = Confirmation.new(command: command, tier: tier, required_text: required_text)
    end

    def handle_confirmation(msg)
      return nil unless msg.is_a?(Chamomile::KeyMsg)

      @confirmation.handle_key(msg.key)

      if @confirmation.confirmed?
        command = @confirmation.command
        panel_type = current_panel.type
        @confirmation = nil

        # Special handling for credentials decryption
        if @pending_credential
          credential = @pending_credential
          @pending_credential = nil
          return decrypt_credentials_cmd(credential)
        end

        return run_rails_cmd(command, panel_type)
      elsif @confirmation.cancelled?
        @pending_credential = nil
        @confirmation = nil
        set_flash("Cancelled.")
      end

      nil
    end

    # ─── Message handling (from MessageHandler) ───────────

    def handle_tick
      @flash.tick

      # Detect server state changes
      current_state = @server.state
      if current_state != @last_server_state
        case current_state
        when :running
          set_flash("Server running on port #{@server.port}")
        when :stopped
          set_flash("Server stopped.") if @last_server_state == :running
        when :error
          set_flash("Server error — check detail pane")
        end
        @last_server_state = current_state
        update_detail_content if current_panel.type == :server
      elsif current_panel.type == :server && @server.log_changed?
        # Refresh server detail content only when log has new output
        update_detail_content
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

        # About/stats/notes now come from the same rails runner invocation
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

      # Reload panel data after command
      case msg.panel
      when :database, :models
        return load_introspect_cmd
      when :gems
        return load_gems_cmd
      when :tests
        return load_tests_cmd
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
      # Ignore stale results if browser was closed or user navigated to a different table
      return unless @table_browser.visible? && @table_browser.screen == :row_data
      return unless msg.table == @table_browser.selected_table

      if msg.error
        @table_browser.fail_loading(msg.error)
      else
        @table_browser.load_rows(msg.columns, msg.rows)
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
      when :logs
        # Clear and restart — new entries will flow in via tick
        panel.finish_loading(items: [])
        @log_watcher.clear
        set_flash("Log buffer cleared.")
      end
      # :server, :console — no refresh action (avoid stuck Loading state)
      nil
    end

    def handle_undo
      entry = @command_log.last_reversible
      unless entry
        set_flash("Nothing to undo.")
        return nil
      end

      reverse = @command_log.reverse_command(entry)
      unless reverse
        set_flash("Cannot undo.")
        return nil
      end

      start_confirmation(reverse, tier: :yellow)
      nil
    end

    def discover_credentials
      panel = find_panel(:credentials)
      return unless panel

      project_dir = @project.dir
      files = []

      default_enc = File.join(project_dir, "config/credentials.yml.enc")
      default_key = File.join(project_dir, "config/master.key")
      files << CredentialFile.new(
        environment: "development (default)",
        path: default_enc,
        exists: File.exist?(default_enc) && File.exist?(default_key)
      )

      Dir.glob(File.join(project_dir, "config/credentials/*.yml.enc")).each do |enc|
        env = File.basename(enc, ".yml.enc")
        key = File.join(project_dir, "config/credentials/#{env}.key")
        files << CredentialFile.new(
          environment: env,
          path: enc,
          exists: File.exist?(enc) && File.exist?(key)
        )
      end

      panel.finish_loading(items: files)
    end

    def load_fallback_data
      schema_path = File.join(@project.dir, "db/schema.rb")
      if File.exist?(schema_path)
        tables = Parsers::Schema.parse(File.read(schema_path))
        models = tables.map do |table_name, cols|
          ModelInfo.new(name: ViewHelpers.classify_name(table_name), table_name: table_name, columns: cols)
        end
        find_panel(:models).finish_loading(items: models)
      end
    end
  end
end
