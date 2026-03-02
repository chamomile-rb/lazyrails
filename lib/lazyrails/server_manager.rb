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
    end

    def state
      @mutex.synchronize { @state }
    end

    def pid
      @mutex.synchronize { @pid }
    end

    def start
      @mutex.synchronize do
        return if @state == :running || @state == :starting

        @state = :starting
        @log_lines.clear
      end

      port_str = @port.to_s

      @thread = Thread.new do
        env = { "DISABLE_SPRING" => "1", "PORT" => port_str }
        cmd = "#{@project.bin_rails} server -p #{@port}"

        begin
          Open3.popen2e(env, cmd, chdir: @project.dir) do |stdin, output, wait_thr|
            @mutex.synchronize { @pid = wait_thr.pid }
            stdin.close

            output.each_line do |line|
              line = CommandRunner.force_utf8(line)
              @mutex.synchronize do
                @log_lines << line
                @log_lines.shift if @log_lines.size > MAX_LOG_LINES
                @state = :running if @state == :starting && line.include?("Listening on")
              end
            end

            status = wait_thr.value
            @mutex.synchronize do
              @state = status.success? ? :stopped : :error
              @pid = nil
            end
          end
        rescue => e
          @mutex.synchronize do
            @state = :error
            @log_lines << "Error: #{e.message}\n"
            @pid = nil
          end
        end
      end
    end

    def stop
      pid_to_kill = @mutex.synchronize { @pid }
      return unless pid_to_kill

      begin
        Process.kill("TERM", pid_to_kill)

        deadline = Time.now + KILL_TIMEOUT
        loop do
          break if @mutex.synchronize { @pid.nil? }
          break if Time.now >= deadline
          sleep 0.1
        end

        remaining = @mutex.synchronize { @pid }
        Process.kill("KILL", remaining) if remaining
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

    def log_content
      @mutex.synchronize { @log_lines.join }
    end
  end
end
