# frozen_string_literal: true

module LazyRails
  class LogWatcher
    POLL_INTERVAL = 1.0

    def initialize(project)
      @project = project
      @log_path = File.join(project.dir, "log/development.log")
      @mutex = Mutex.new
      @entries = []
      @dirty = false
      @position = 0
      @thread = nil
      @running = false
    end

    def start
      return if @running
      return unless File.exist?(@log_path)

      @running = true
      # Start reading from the end of the file
      @position = File.size(@log_path)

      @thread = Thread.new { watch_loop }
    end

    def stop
      @running = false
      @thread&.join(2)
    end

    def changed?
      @mutex.synchronize { @dirty }
    end

    def take_entries
      @mutex.synchronize do
        @dirty = false
        entries = @entries.dup
        @entries.clear
        entries
      end
    end

    def clear
      @mutex.synchronize do
        @entries.clear
        @dirty = false
      end
    end

    private

    def watch_loop
      while @running
        begin
          check_for_new_content
        rescue
          # Silently ignore read errors
        end
        sleep POLL_INTERVAL
      end
    end

    def check_for_new_content
      return unless File.exist?(@log_path)

      current_size = File.size(@log_path)

      # File was truncated/rotated
      if current_size < @position
        @position = 0
      end

      return if current_size == @position

      new_content = File.open(@log_path, "rb") do |f|
        f.seek(@position)
        f.read
      end

      @position += new_content.bytesize

      return if new_content.nil? || new_content.empty?

      new_content = CommandRunner.force_utf8(new_content)
      parsed = Parsers::LogParser.parse(new_content)

      unless parsed.empty?
        @mutex.synchronize do
          @entries.concat(parsed)
          # Keep only the latest entries to avoid unbounded growth
          @entries = @entries.last(500) if @entries.size > 500
          @dirty = true
        end
      end
    end
  end
end
