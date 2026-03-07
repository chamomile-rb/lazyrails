# frozen_string_literal: true

# This script is executed via: bin/rails runner lib/lazyrails/jobs_query_runner.rb <action> [args_json]
# Queries Solid Queue tables and returns JSON to stdout.
#
# Actions:
#   stats_and_list <filter_json>    → counts + queue depths + job list (single boot)
#   stats                           → dashboard counts + queue depths
#   list <filter_json>              → jobs list (status, class_name, queue, limit, offset)
#   retry <failed_execution_id>     → retry a single failed job
#   retry_all <filter_json>         → retry all matching failed jobs
#   discard <failed_execution_id>   → discard a single failed job
#   dispatch <job_id>               → dispatch a scheduled job now
#   discard_scheduled <job_id>      → discard a scheduled job
#   toggle_pause <queue_name>       → pause/resume a queue
#   enqueue_recurring <task_key>    → enqueue a recurring task now
#   workers                         → list worker processes
#   recurring                       → list recurring tasks

require "json"

unless defined?(SolidQueue)
  puts JSON.generate({ available: false })
  exit
end

action = ARGV[0] || "stats"
arg = ARGV[1]

# ─── Helper methods ──────────────────────────────────────

def fetch_counts
  {
    ready: SolidQueue::ReadyExecution.count,
    claimed: SolidQueue::ClaimedExecution.count,
    failed: SolidQueue::FailedExecution.count,
    scheduled: SolidQueue::ScheduledExecution.count,
    blocked: SolidQueue::BlockedExecution.count,
    total: SolidQueue::Job.count,
    finished: SolidQueue::Job.finished.count
  }
end

def apply_class_filter(scope, class_filter)
  return scope unless class_filter.present?

  scope.merge(SolidQueue::Job.where("class_name LIKE ?", "%#{class_filter}%"))
end

def fetch_jobs(params) # rubocop:disable Metrics
  status = params["status"] || "all"
  class_filter = params["class_name"]
  queue_filter = params["queue"]
  limit = (params["limit"] || 100).to_i
  offset = (params["offset"] || 0).to_i

  jobs = []
  total = 0

  case status
  when "all"
    # Show recent jobs across all statuses (most recent first)
    scope = SolidQueue::Job.all
    scope = scope.where(queue_name: queue_filter) if queue_filter.present?
    scope = scope.where("class_name LIKE ?", "%#{class_filter}%") if class_filter.present?
    total = scope.count
    page_jobs = scope.order(created_at: :desc).offset(offset).limit(limit).to_a
    job_ids = page_jobs.map(&:id)

    # Batch-load execution status to avoid N+1 queries
    failed_ids   = SolidQueue::FailedExecution.where(job_id: job_ids).pluck(:job_id).to_set
    claimed_ids  = SolidQueue::ClaimedExecution.where(job_id: job_ids).pluck(:job_id).to_set
    scheduled_ids = SolidQueue::ScheduledExecution.where(job_id: job_ids).pluck(:job_id).to_set
    blocked_ids = SolidQueue::BlockedExecution.where(job_id: job_ids).pluck(:job_id).to_set

    page_jobs.each do |job|
      st = if job.finished_at
             "finished"
           elsif failed_ids.include?(job.id)
             "failed"
           elsif claimed_ids.include?(job.id)
             "claimed"
           elsif scheduled_ids.include?(job.id)
             "scheduled"
           elsif blocked_ids.include?(job.id)
             "blocked"
           else
             "ready"
           end
      jobs << job_hash(job, status: st, arguments: job.arguments)
    end

  when "ready"
    scope = SolidQueue::ReadyExecution.joins(:job).includes(:job)
    scope = scope.where(queue_name: queue_filter) if queue_filter.present?
    scope = apply_class_filter(scope, class_filter)
    total = scope.count
    scope.order(priority: :asc, job_id: :asc).offset(offset).limit(limit).each do |re|
      job = re.job
      next unless job

      jobs << job_hash(job, status: "ready", arguments: job.arguments)
    end

  when "claimed"
    scope = SolidQueue::ClaimedExecution.joins(:job).includes(:job)
    scope = scope.merge(SolidQueue::Job.where(queue_name: queue_filter)) if queue_filter.present?
    scope = apply_class_filter(scope, class_filter)
    total = scope.count
    scope.order(job_id: :asc).offset(offset).limit(limit).each do |ce|
      job = ce.job
      next unless job

      jobs << job_hash(job, status: "claimed", arguments: job.arguments,
                            worker_id: ce.process_id, started_at: ce.created_at&.iso8601)
    end

  when "failed"
    scope = SolidQueue::FailedExecution.joins(:job).includes(:job)
    scope = scope.merge(SolidQueue::Job.where(queue_name: queue_filter)) if queue_filter.present?
    scope = apply_class_filter(scope, class_filter)
    total = scope.count
    scope.order(created_at: :desc).offset(offset).limit(limit).each do |fe|
      job = fe.job
      next unless job

      jobs << job_hash(job, status: "failed", arguments: job.arguments,
                            fe_id: fe.id,
                            error_class: fe.exception_class || "Unknown",
                            error_message: fe.message || "No message",
                            backtrace: (fe.backtrace || []).first(30),
                            failed_at: fe.created_at&.iso8601)
    end

  when "scheduled"
    scope = SolidQueue::ScheduledExecution.joins(:job).includes(:job)
    scope = scope.merge(SolidQueue::Job.where(queue_name: queue_filter)) if queue_filter.present?
    scope = apply_class_filter(scope, class_filter)
    total = scope.count
    scope.order(scheduled_at: :asc, priority: :asc).offset(offset).limit(limit).each do |se|
      job = se.job
      next unless job

      jobs << job_hash(job, status: "scheduled", arguments: job.arguments,
                            scheduled_at: se.scheduled_at&.iso8601)
    end

  when "blocked"
    scope = SolidQueue::BlockedExecution.joins(:job).includes(:job)
    scope = scope.merge(SolidQueue::Job.where(queue_name: queue_filter)) if queue_filter.present?
    scope = apply_class_filter(scope, class_filter)
    total = scope.count
    scope.order(job_id: :asc).offset(offset).limit(limit).each do |be|
      job = be.job
      next unless job

      jobs << job_hash(job, status: "blocked", arguments: job.arguments,
                            concurrency_key: job.concurrency_key,
                            expires_at: be.expires_at&.iso8601)
    end

  when "finished"
    scope = SolidQueue::Job.finished
    scope = scope.where(queue_name: queue_filter) if queue_filter.present?
    scope = scope.where("class_name LIKE ?", "%#{class_filter}%") if class_filter.present?
    total = scope.count
    scope.order(finished_at: :desc).offset(offset).limit(limit).each do |job|
      jobs << job_hash(job, status: "finished", arguments: job.arguments,
                            finished_at: job.finished_at&.iso8601)
    end
  end

  { jobs: jobs, total: total }
end

def job_hash(job, status:, **extras)
  {
    id: job.id, class_name: job.class_name, queue_name: job.queue_name,
    priority: job.priority, status: status, active_job_id: job.active_job_id,
    created_at: job.created_at&.iso8601
  }.merge(extras)
end

# ─── Main dispatch ───────────────────────────────────────

begin
  case action

  # ─── Combined stats + list (avoids double Rails boot) ──
  when "stats_and_list"
    params = arg ? JSON.parse(arg) : {}
    counts = fetch_counts
    queue_depths = SolidQueue::ReadyExecution.group(:queue_name).count
    result = fetch_jobs(params)

    puts JSON.generate({
                         available: true, action: "stats_and_list",
                         counts: counts, queue_depths: queue_depths,
                         jobs: result[:jobs], total: result[:total]
                       })

  # ─── Dashboard stats only ──────────────────────────────
  when "stats"
    counts = fetch_counts
    queue_depths = SolidQueue::ReadyExecution.group(:queue_name).count
    processes = SolidQueue::Process.group(:kind).count

    puts JSON.generate({
                         available: true, action: "stats",
                         counts: counts, queue_depths: queue_depths, processes: processes
                       })

  # ─── List jobs by status ───────────────────────────────
  when "list"
    params = arg ? JSON.parse(arg) : {}
    result = fetch_jobs(params)
    puts JSON.generate({ available: true, action: "list", jobs: result[:jobs], total: result[:total] })

  # ─── Retry single failed job ───────────────────────────
  when "retry"
    fe = SolidQueue::FailedExecution.find(arg.to_i)
    fe.retry
    puts JSON.generate({ available: true, action: "retry", success: true })

  # ─── Retry all failed jobs ────────────────────────────
  when "retry_all"
    params = arg ? JSON.parse(arg) : {}
    scope = SolidQueue::FailedExecution.joins(:job)
    scope = scope.merge(SolidQueue::Job.where(queue_name: params["queue"])) if params["queue"].present?
    scope = apply_class_filter(scope, params["class_name"])
    count = scope.count
    if count.positive?
      job_ids = scope.pluck(:job_id)
      SolidQueue::FailedExecution.retry_all(SolidQueue::Job.where(id: job_ids))
    end
    puts JSON.generate({ available: true, action: "retry_all", success: true, count: count })

  # ─── Discard single failed job ─────────────────────────
  when "discard"
    fe = SolidQueue::FailedExecution.find(arg.to_i)
    fe.discard
    puts JSON.generate({ available: true, action: "discard", success: true })

  # ─── Dispatch scheduled job now ────────────────────────
  when "dispatch"
    SolidQueue::ScheduledExecution.dispatch_jobs([arg.to_i])
    puts JSON.generate({ available: true, action: "dispatch", success: true })

  # ─── Discard scheduled job ────────────────────────────
  when "discard_scheduled"
    se = SolidQueue::ScheduledExecution.find_by!(job_id: arg.to_i)
    se.discard
    puts JSON.generate({ available: true, action: "discard_scheduled", success: true })

  # ─── Toggle queue pause ───────────────────────────────
  when "toggle_pause"
    queue = SolidQueue::Queue.find_by_name(arg)
    if queue.paused?
      queue.resume
      puts JSON.generate({ available: true, action: "toggle_pause", paused: false })
    else
      queue.pause
      puts JSON.generate({ available: true, action: "toggle_pause", paused: true })
    end

  # ─── List workers/processes ────────────────────────────
  when "workers"
    workers = SolidQueue::Process.where(kind: "Worker").order(:id).map do |proc|
      {
        id: proc.id, kind: proc.kind, pid: proc.pid,
        hostname: proc.hostname, name: proc.name,
        last_heartbeat_at: proc.last_heartbeat_at&.iso8601,
        metadata: proc.metadata, created_at: proc.created_at&.iso8601
      }
    end
    puts JSON.generate({ available: true, action: "workers", workers: workers })

  # ─── List recurring tasks ─────────────────────────────
  when "recurring"
    tasks = SolidQueue::RecurringTask.all.to_a
    last_enqueued = if tasks.any?
                      SolidQueue::RecurringExecution
                        .where(task_key: tasks.map(&:key))
                        .group(:task_key)
                        .maximum(:run_at)
                    else
                      {}
                    end
    result = tasks.map do |task|
      {
        key: task.key, class_name: task.class_name, command: task.command,
        schedule: task.schedule, queue_name: task.queue_name,
        priority: task.priority, last_enqueued_at: last_enqueued[task.key]&.iso8601,
        next_time: task.next_time&.iso8601
      }
    end
    puts JSON.generate({ available: true, action: "recurring", tasks: result })

  # ─── Enqueue recurring task now ────────────────────────
  when "enqueue_recurring"
    task = SolidQueue::RecurringTask.find_by!(key: arg)
    task.enqueue(at: Time.now)
    puts JSON.generate({ available: true, action: "enqueue_recurring", success: true })

  else
    puts JSON.generate({ available: true, error: "Unknown action: #{action}" })
  end
rescue ActiveRecord::RecordNotFound => e
  puts JSON.generate({ available: true, action: action, success: false, error: "Not found: #{e.message}" })
rescue StandardError => e
  puts JSON.generate({ available: true, action: action, success: false, error: "#{e.class}: #{e.message}" })
end
