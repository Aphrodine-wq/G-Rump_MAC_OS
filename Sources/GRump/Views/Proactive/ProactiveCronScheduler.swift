import Foundation
import OSLog

// MARK: - Cron Schedule

/// Schedule types for proactive cron jobs.
enum CronSchedule: Sendable {
    case interval(TimeInterval)
    case dailyAt(hour: Int, minute: Int)
    case oneShot(Date)
}

// MARK: - Cron Job Result

enum CronJobResult: Sendable {
    case success
    case error(String)
    case skip
}

// MARK: - Proactive Cron Job

/// Mirrors OpenClaw's CronJobState from `service/state.ts`.
struct ProactiveCronJob: Identifiable, Sendable {
    let id: String
    let label: String
    var schedule: CronSchedule
    var handler: @Sendable () async -> CronJobResult
    var lastRun: Date?
    var nextRun: Date?
    var errorCount: Int = 0
    var backoffMs: Int = 0
    var disabled: Bool = false
    var staggerMs: Int = 0

    static let maxBackoffMs = 3_600_000
    static let maxConsecutiveFailures = 5
}

// MARK: - Proactive Cron Scheduler

/// Actor-based cron scheduler mirroring OpenClaw's CronService architecture.
/// Uses a single DispatchSourceTimer for the next-due job (not one timer per job).
/// Supports exponential backoff, stagger, and auto-disable on repeated failures.
actor ProactiveCronScheduler {

    private var jobs: [String: ProactiveCronJob] = [:]
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private let logger = GRumpLogger.proactive
    private let queue = DispatchQueue(label: "com.grump.cron", qos: .utility)

    // MARK: - Job Management

    /// Add a new cron job. Mirrors OpenClaw's job registration.
    func addJob(
        id: String,
        label: String,
        schedule: CronSchedule,
        staggerMaxMs: Int = 5000,
        handler: @escaping @Sendable () async -> CronJobResult
    ) {
        let stagger = Int.random(in: 0...staggerMaxMs)
        var job = ProactiveCronJob(
            id: id,
            label: label,
            schedule: schedule,
            handler: handler,
            staggerMs: stagger
        )
        job.nextRun = computeNextRun(schedule: schedule, stagger: stagger)
        jobs[id] = job
        logger.info("Cron job added: \(id) (\(label))")

        if isRunning { armTimer() }
    }

    /// Remove a cron job by ID.
    func removeJob(id: String) {
        jobs.removeValue(forKey: id)
        logger.info("Cron job removed: \(id)")
        if isRunning { armTimer() }
    }

    /// Pause a job (keeps it registered but won't fire).
    func pauseJob(id: String) {
        jobs[id]?.disabled = true
        logger.info("Cron job paused: \(id)")
    }

    /// Resume a paused job.
    func resumeJob(id: String) {
        guard var job = jobs[id] else { return }
        job.disabled = false
        job.errorCount = 0
        job.backoffMs = 0
        job.nextRun = computeNextRun(schedule: job.schedule, stagger: job.staggerMs)
        jobs[id] = job
        logger.info("Cron job resumed: \(id)")
        if isRunning { armTimer() }
    }

    /// Trigger a job immediately, ignoring its schedule.
    func triggerNow(id: String) {
        guard var job = jobs[id], !job.disabled else { return }
        job.nextRun = Date()
        jobs[id] = job
        armTimer()
    }

    // MARK: - Lifecycle

    /// Start the scheduler. Mirrors OpenClaw's CronService start.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        logger.info("CronScheduler started with \(self.jobs.count) jobs")
        armTimer()
    }

    /// Stop the scheduler and cancel the timer.
    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        logger.info("CronScheduler stopped")
    }

    // MARK: - Timer Management

    /// Single timer pattern from OpenClaw's `service/timer.ts`.
    /// Computes the next-due job and sets one timer for it.
    private func armTimer() {
        timer?.cancel()
        timer = nil

        guard isRunning else { return }

        // Find the next job due to run
        let now = Date()
        let activeJobs = jobs.values.filter { !$0.disabled && $0.nextRun != nil }
        guard let nextJob = activeJobs.min(by: { ($0.nextRun ?? .distantFuture) < ($1.nextRun ?? .distantFuture) }),
              let nextRunDate = nextJob.nextRun else { return }

        let delay = max(0, nextRunDate.timeIntervalSince(now))

        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + delay)
        newTimer.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.tick()
            }
        }
        newTimer.resume()
        timer = newTimer
    }

    /// Execute all due jobs and re-arm the timer.
    private func tick() {
        let now = Date()
        var jobsToRun: [String] = []

        for (id, job) in jobs {
            guard !job.disabled, let nextRun = job.nextRun, nextRun <= now else { continue }
            jobsToRun.append(id)
        }

        for id in jobsToRun {
            guard let job = jobs[id] else { continue }
            let handler = job.handler

            Task { [weak self] in
                guard let self else { return }
                let result = await handler()
                await self.applyJobResult(jobId: id, result: result)
            }
        }

        // Re-arm for next cycle
        if isRunning {
            armTimer()
        }
    }

    // MARK: - Result Handling

    /// Apply job result with exponential backoff on failure.
    /// Mirrors OpenClaw's `applyJobResult()` from `service/ops.ts`.
    private func applyJobResult(jobId: String, result: CronJobResult) {
        guard var job = jobs[jobId] else { return }

        switch result {
        case .success:
            job.errorCount = 0
            job.backoffMs = 0
            job.lastRun = Date()
            job.nextRun = computeNextRun(schedule: job.schedule, stagger: job.staggerMs)
            logger.debug("Cron job \(jobId) completed successfully")

        case .error(let message):
            job.errorCount += 1
            job.lastRun = Date()

            // Exponential backoff: double backoff, cap at maxBackoffMs
            if job.backoffMs == 0 {
                job.backoffMs = 5000
            } else {
                job.backoffMs = min(job.backoffMs * 2, ProactiveCronJob.maxBackoffMs)
            }

            // Auto-disable after too many consecutive failures
            if job.errorCount >= ProactiveCronJob.maxConsecutiveFailures {
                job.disabled = true
                logger.warning("Cron job \(jobId) auto-disabled after \(job.errorCount) consecutive failures")
            } else {
                let backoffInterval = TimeInterval(job.backoffMs) / 1000.0
                job.nextRun = Date().addingTimeInterval(backoffInterval)
                logger.warning("Cron job \(jobId) failed (\(job.errorCount)x): \(message). Backoff: \(job.backoffMs)ms")
            }

        case .skip:
            job.lastRun = Date()
            job.nextRun = computeNextRun(schedule: job.schedule, stagger: job.staggerMs)
        }

        jobs[jobId] = job

        if isRunning { armTimer() }
    }

    // MARK: - Schedule Computation

    private func computeNextRun(schedule: CronSchedule, stagger: Int) -> Date {
        let staggerInterval = TimeInterval(stagger) / 1000.0
        let now = Date()

        switch schedule {
        case .interval(let seconds):
            return now.addingTimeInterval(seconds + staggerInterval)

        case .dailyAt(let hour, let minute):
            var calendar = Calendar.current
            calendar.timeZone = .current
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard var targetDate = calendar.date(from: components) else {
                return now.addingTimeInterval(86400)
            }

            if targetDate <= now {
                targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? now.addingTimeInterval(86400)
            }

            return targetDate.addingTimeInterval(staggerInterval)

        case .oneShot(let date):
            return date.addingTimeInterval(staggerInterval)
        }
    }

    // MARK: - Introspection

    /// Get status of all registered jobs.
    func allJobs() -> [ProactiveCronJob] {
        Array(jobs.values).sorted { $0.id < $1.id }
    }

    /// Heartbeat log — periodic status dump. Mirrors OpenClaw's heartbeat function.
    func heartbeat() {
        let active = jobs.values.filter { !$0.disabled }.count
        let disabled = jobs.values.filter { $0.disabled }.count
        logger.info("CronScheduler heartbeat: \(active) active, \(disabled) disabled, \(self.jobs.count) total")
    }
}
