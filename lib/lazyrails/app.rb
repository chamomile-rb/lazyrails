# frozen_string_literal: true

module LazyRails
  # Custom messages for async operations
  TestFinishedEvent = Data.define(:path, :status, :output, :command_entry) do
    def initialize(command_entry: nil, **kwargs)
      super
    end
  end

  class App
    include Chamomile::Model
    include Chamomile::Commands
    include Renderer
    include DataLoader
    include PanelHandlers
    include MessageHandlers

    GENERATOR_TYPES = [
      { type: "model",      label: "Model",      placeholder: "User name:string email:string" },
      { type: "migration",  label: "Migration",  placeholder: "AddStatusToOrders status:integer" },
      { type: "controller", label: "Controller", placeholder: "Articles index show" },
      { type: "scaffold",   label: "Scaffold",   placeholder: "Post title:string body:text" },
      { type: "job",        label: "Job",        placeholder: "ProcessPayment" },
      { type: "mailer",     label: "Mailer",     placeholder: "UserMailer welcome reset_password" },
      { type: "channel",    label: "Channel",    placeholder: "Chat" },
      { type: "stimulus",   label: "Stimulus",   placeholder: "toggle" }
    ].freeze

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
      { type: :mailers,  title: "Mailers" },
      { type: :jobs,     title: "Jobs" }
    ].freeze

    LEFT_WIDTH_RATIO = 0.30
    UI_TICK_SECONDS = 1.0

    def initialize(project)
      @project = project
      @config = Config.load(project.dir)
      @panels = PANEL_DEFS.map { |d| Panel.new(type: d[:type], title: d[:title]) }

      @panels << Panel.new(type: :custom, title: "Custom") unless @config.empty?

      @focused_panel = 0
      @width = 80
      @height = 24
      @command_log = CommandLog.new
      @server = ServerManager.new(project)
      @log_watcher = LogWatcher.new(project)
      @detail_viewport = Chamomile::Viewport.new(width: 40, height: 20)

      # Component objects
      @flash = Flash.new
      @command_log_overlay = CommandLogOverlay.new(@command_log)
      @menu = MenuOverlay.new
      @table_browser = TableBrowser.new
      @input_mode = InputMode.new
      @welcome = WelcomeOverlay.new
      @help = HelpOverlay.new
      @user_settings = UserSettings.new
      @generator_wizard = GeneratorWizard.new

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
      @confirmation = nil
      @route_grouped = false
      @last_server_state = :stopped
      @jobs_filter = "all"
      @jobs_available = nil
      @jobs_tick_counter = 0
      @pending_job_action = nil

      # Caches
      @detail_content = ""
      @file_cache = FileCache.new
      @panel_render_cache = {}
    end

    # ─── Chamomile lifecycle ──────────────────────────────

    def start
      unless @config.empty?
        custom_panel = find_panel(:custom)
        custom_panel&.finish_loading(items: @config.custom_commands)
      end

      # These panels are event-driven, not loaded from a command
      find_panel(:server)&.finish_loading(items: [])
      find_panel(:console)&.finish_loading(items: [])
      find_panel(:logs)&.finish_loading(items: [])
      find_panel(:jobs)&.finish_loading(items: [])

      discover_credentials
      @welcome.show unless @user_settings.welcome_seen?

      @log_watcher.start

      batch(
        load_introspect_cmd,
        load_gems_cmd,
        load_tests_cmd,
        load_mailers_cmd,
        load_jobs_cmd(@jobs_filter),
        ui_tick
      )
    end

    def update(msg)
      return handle_welcome(msg) if @welcome.visible? && msg.is_a?(Chamomile::KeyEvent)
      return handle_help_key(msg) if @help.visible? && msg.is_a?(Chamomile::KeyEvent)
      return handle_generator_wizard(msg) if @generator_wizard.visible? && msg.is_a?(Chamomile::KeyEvent)
      return handle_confirmation(msg) if @confirmation
      return handle_input_mode(msg) if @input_mode.active?

      case msg
      when Chamomile::ResizeEvent then handle_resize(msg)
      when Chamomile::KeyEvent        then return handle_key(msg)
      when Chamomile::TickEvent       then return handle_tick
      when Chamomile::InterruptEvent  then return shutdown
      when IntrospectLoadedEvent      then return handle_introspect_loaded(msg)
      when GemsLoadedEvent            then handle_gems_loaded(msg)
      when TestsLoadedEvent           then handle_tests_loaded(msg)
      when CommandFinishedEvent       then return handle_command_finished(msg)
      when TestFinishedEvent          then handle_test_finished(msg)
      when TableRowsLoadedEvent       then handle_table_rows_loaded(msg)
      when EvalFinishedEvent          then handle_eval_finished(msg)
      when CredentialsLoadedEvent     then handle_credentials_loaded(msg)
      when MailersLoadedEvent         then handle_mailers_loaded(msg)
      when MailerPreviewLoadedEvent   then handle_mailer_preview_loaded(msg)
      when JobsLoadedEvent            then handle_jobs_loaded(msg)
      when JobActionEvent             then return handle_job_action(msg)
      end

      nil
    end

    def view
      left_width = (@width * LEFT_WIDTH_RATIO).to_i
      right_width = @width - left_width - 1

      left_content = render_left_panels(left_width)
      right_content = render_right_pane(right_width)

      layout = Chamomile.horizontal([left_content, " ", right_content], align: :top)

      base = if @input_mode.active?
               "#{layout}\n#{render_filter_bar}"
             else
               "#{layout}\n#{render_status_bar}"
             end

      # Overlays composited on top of the base layout
      if @welcome.visible?
        overlay_on(base, @welcome.render(width: @width, height: @height))
      elsif @help.visible?
        overlay_on(base, @help.render(width: @width, height: @height))
      elsif @command_log_overlay.visible?
        overlay_on(base, render_command_log_box)
      elsif @table_browser.visible?
        overlay_on(base, render_table_browser_box)
      elsif @generator_wizard.visible?
        overlay_on(base, @generator_wizard.render(width: @width, height: @height))
      elsif @menu.visible?
        overlay_on(base, @menu.render(width: @width, height: @height))
      elsif @confirmation
        overlay_on(base, render_confirmation_box)
      else
        base
      end
    end

    private

    def overlay_on(base, popup_box)
      ViewHelpers.overlay(base, popup_box, @width, @height)
    end

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

    def handle_welcome(msg)
      signal = @welcome.handle_key(msg.key)
      case signal
      when :dismiss
        @welcome.hide
      when :dismiss_forever
        @welcome.hide
        @user_settings.mark_welcome_seen!
      when :quit
        return shutdown
      end
      nil
    end

    def handle_help_key(msg)
      signal = @help.handle_key(msg.key)
      return shutdown if signal == :quit

      nil
    end

    def handle_generator_wizard(msg)
      result = @generator_wizard.handle_key(msg.key)
      return nil unless result.is_a?(Hash)

      case result[:action]
      when :run
        panel_type = generator_panel_type(@generator_wizard.gen_type)
        return run_rails_cmd(result[:command], panel_type)
      when :cancel
        nil
      end
    end

    def generator_panel_type(gen_type)
      case gen_type
      when "migration" then :database
      else :models
      end
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
      File.directory?(File.join(@project.dir, "spec")) ? "bundle exec rspec" : "bin/rails test"
    end

    def test_failed_command
      if File.directory?(File.join(@project.dir,
                                   "spec"))
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
                  r.action.split("#").first
                rescue StandardError
                  "zzz"
                end
              end
      panel.finish_loading(items: items)
      panel.reset_cursor
    end

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
        cmd = ["bin/rails", "credentials:show", "--environment", env]
        start_confirmation(cmd, tier: :yellow)
        @pending_credential = item
      else
        set_flash("Key file missing for #{item.environment}")
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

    # ─── Key handling ─────────────────────────────────────

    def handle_key(msg)
      if @command_log_overlay.visible?
        signal = @command_log_overlay.handle_key(msg.key)
        return shutdown if signal == :quit

        return nil
      end

      if @menu.visible?
        result = @menu.handle_key(msg.key)
        return shutdown if result == :quit
        return handle_menu_action(result) if result && result != :quit

        return nil
      end

      return handle_table_browser_key(msg) if @table_browser.visible?

      if msg.key == :tab && msg.shift?
        clear_panel_state
        @focused_panel = (@focused_panel - 1) % @panels.size
        update_detail_content
        return nil
      end

      case msg.key
      when "q"  then return shutdown
      when "?"  then @help.show
      when "L"  then @command_log_overlay.show
      when :tab, :right, "l"
        clear_panel_state
        @focused_panel = (@focused_panel + 1) % @panels.size
        update_detail_content
      when :left, "h"
        clear_panel_state
        @focused_panel = (@focused_panel - 1) % @panels.size
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
      when :enter then return handle_enter
      when "/"   then start_filter
      when "G"   then show_generator_menu
      when "x"   then show_panel_menu
      when "R"   then return handle_refresh
      when "z"   then return handle_undo
      else       return handle_panel_key(msg)
      end

      nil
    end

    def handle_table_browser_key(msg)
      signal = @table_browser.handle_key(msg.key)
      case signal
      when :quit  then return shutdown
      when :close then @table_browser.hide
      when Hash
        case signal[:action]
        when :load_table
          return load_table_rows_cmd(signal[:table])
        when :input_where
          @input_mode.start_input(:table_where, prompt: "WHERE: ", placeholder: "id > 5 AND name LIKE '%test%'")
        when :input_order
          @input_mode.start_input(:table_order, prompt: "ORDER BY: ", placeholder: "created_at DESC")
        end
      end
      nil
    end

    # ─── Input mode ───────────────────────────────────────

    def start_filter
      return unless %i[routes models tests gems rake console logs mailers jobs custom].include?(current_panel.type)

      @input_mode.start_filter
    end

    def handle_input_mode(msg)
      return nil unless msg.is_a?(Chamomile::KeyEvent)

      signal = @input_mode.handle_key(msg)

      case signal
      when :cancelled
        @input_mode.deactivate
        current_panel.filter_text = ""
        current_panel.reset_cursor
      when Hash
        case signal[:action]
        when :submitted
          @input_mode.deactivate
          return handle_input_submit(signal[:value], signal[:purpose])
        when :changed
          current_panel.filter_text = signal[:value]
          current_panel.reset_cursor
        end
      end

      nil
    end

    # ─── Confirmation ─────────────────────────────────────

    def start_confirmation(command, tier: nil, required_text: nil)
      tier ||= Confirmation.detect_tier(command)
      return run_rails_cmd(command, current_panel.type) if tier == :green

      required_text ||= current_panel.title.downcase if tier == :red
      @confirmation = Confirmation.new(command: command, tier: tier, required_text: required_text)
    end

    def handle_confirmation(msg)
      return nil unless msg.is_a?(Chamomile::KeyEvent)

      @confirmation.handle_key(msg.key)

      if @confirmation.confirmed?
        command = @confirmation.command
        panel_type = current_panel.type
        @confirmation = nil

        if @pending_credential
          credential = @pending_credential
          @pending_credential = nil
          return decrypt_credentials_cmd(credential)
        end

        if @pending_job_action
          pending = @pending_job_action
          @pending_job_action = nil
          case pending.action
          when :retry          then return retry_job_cmd(pending.fe_id)
          when :discard        then return discard_job_cmd(pending.fe_id)
          when :retry_all      then return retry_all_jobs_cmd
          when :dispatch       then return dispatch_job_cmd(pending.job_id)
          when :discard_scheduled then return discard_scheduled_job_cmd(pending.job_id)
          end
        end

        return run_rails_cmd(command, panel_type)
      elsif @confirmation.cancelled?
        @pending_credential = nil
        @pending_job_action = nil
        @confirmation = nil
        set_flash("Cancelled.")
      end

      nil
    end

    # ─── Other ────────────────────────────────────────────

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
        files << CredentialFile.new(environment: env, path: enc, exists: File.exist?(enc) && File.exist?(key))
      end

      panel.finish_loading(items: files)
    end

    def load_fallback_data
      schema_path = File.join(@project.dir, "db/schema.rb")
      return unless File.exist?(schema_path)

      tables = Parsers::Schema.parse(File.read(schema_path))
      models = tables.map do |table_name, cols|
        ModelInfo.new(name: ViewHelpers.classify_name(table_name), table_name: table_name, columns: cols)
      end
      find_panel(:models).finish_loading(items: models)
    end
  end
end
