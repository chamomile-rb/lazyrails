# frozen_string_literal: true

module LazyRails
  class ServerManager
    MAX_LOG_LINES = 2000
    KILL_TIMEOUT = 5

    attr_reader :port

    def initialize(project)
      @project = project
      @state = :stopped
      @port = 3000
      @pid = nil
      @log_lines = []
      @thread = nil
      @mutex = Mutex.new
      @log_dirty = false
      @uses_bin_dev = File.exist?(File.join(project.dir, "bin/dev"))
    end

    def state
      @mutex.synchronize { @state }
    end

    def pid
      @mutex.synchronize { @pid }
    end

    def uses_bin_dev?
      @uses_bin_dev
    end

    def start
      @mutex.synchronize do
        return if @state == :running || @state == :starting

        @state = :starting
        @log_lines.clear
        @log_dirty = true
      end

      port_str = @port.to_s

      @thread = Thread.new do
        env = { "DISABLE_SPRING" => "1", "PORT" => port_str }
        cmd = if @uses_bin_dev
                "bin/dev"
              else
                "#{@project.bin_rails} server -p #{@port}"
              end

        begin
          # Clear Bundler env so the Rails app uses its own Gemfile
          Bundler.with_unbundled_env do
            # Use pgroup for process group kill (needed for foreman/bin/dev)
            Open3.popen2e(env, cmd, chdir: @project.dir, pgroup: true) do |stdin, output, wait_thr|
              @mutex.synchronize { @pid = wait_thr.pid }
              stdin.close

              output.each_line do |line|
                line = CommandRunner.force_utf8(line)
                @mutex.synchronize do
                  @log_lines << line
                  @log_lines.shift if @log_lines.size > MAX_LOG_LINES
                  @log_dirty = true
                  @state = :running if @state == :starting && server_ready?(line)
                end
              end

              status = wait_thr.value
              @mutex.synchronize do
                @state = status.success? ? :stopped : :error
                @pid = nil
              end
            end
          end
        rescue StandardError => e
          @mutex.synchronize do
            @state = :error
            @log_lines << "Error: #{e.message}\n"
            @log_dirty = true
            @pid = nil
          end
        end
      end
    end

    def stop
      pid_to_kill = @mutex.synchronize { @pid }
      return unless pid_to_kill

      begin
        # Kill the process group so foreman children (puma, vite) also die
        Process.kill("TERM", -pid_to_kill)

        deadline = Time.now + KILL_TIMEOUT
        loop do
          break if @mutex.synchronize { @pid.nil? }
          break if Time.now >= deadline

          sleep 0.1
        end

        remaining = @mutex.synchronize { @pid }
        Process.kill("KILL", -remaining) if remaining
      rescue Errno::ESRCH, Errno::EPERM
        # Process already gone or no permission
      end

      @mutex.synchronize do
        @state = :stopped
        @pid = nil
      end
    end

    def restart
      stop
      start
    end

    def port=(new_port)
      @port = new_port.to_i
    end

    def running?
      @mutex.synchronize { @state == :running }
    end

    def log_changed?
      @mutex.synchronize { @log_dirty }
    end

    def log_content
      @mutex.synchronize do
        @log_dirty = false
        @log_lines.join
      end
    end

    private

    # Detect server startup across common Ruby servers
    def server_ready?(line)
      line.include?("Listening on") ||     # Puma
        line.include?("listening on") ||   # Falcon, Vite
        line.include?("port=") ||          # WEBrick ("port=3000")
        line.include?("Ctrl-C to stop")    # WEBrick, Thin
    end
  end
end
