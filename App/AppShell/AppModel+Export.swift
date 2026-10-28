import AppKit
import PixtamerKit

extension AppModel {
    // MARK: Destination

    @discardableResult
    func chooseDestination() -> Bool {
        guard let url = FilePanels.chooseDestination(startingAt: destination.url) else { return false }
        destination.set(url)
        if preferences.destinationBehavior == .rememberLast {
            preferences.rememberedDestinationBookmark = destination.makeBookmark()
            savePreferences()
        }
        return true
    }

    func restoreRememberedDestination() {
        guard preferences.destinationBehavior == .rememberLast, let bookmark = preferences.rememberedDestinationBookmark else { return }
        let result = destination.restore(from: bookmark)
        if !result.restored {
            preferences.rememberedDestinationBookmark = nil
            savePreferences()
        } else if let refreshed = result.refreshed {
            preferences.rememberedDestinationBookmark = refreshed
            savePreferences()
        }
    }

    // MARK: Export

    /// Plans the export and starts it, asking first if existing files would be replaced.
    func startExport() {
        guard canStartExport else { return }
        if destination.url == nil || !destination.exists {
            guard chooseDestination() else { return }
        }
        guard let folder = destination.url else { return }

        let plan = ExportPlanner().plan(inputs: batch.inputs, settings: settings, destination: folder)
        guard plan.writeCount > 0 else {
            notice = AppNotice(
                title: "Nothing to export",
                message: "With the current settings every output would be skipped (for example, all images are smaller than the requested sizes and upscaling is off)."
            )
            return
        }
        let replacements = plan.variants.filter { $0.notes.contains(.replacesExisting) }.count
        if replacements > 0 {
            pendingReplacement = PendingReplacement(plan: plan, count: replacements)
            return
        }
        run(plan, isRetry: false)
    }

    func confirmReplacement(_ pending: PendingReplacement, keepBoth: Bool) {
        pendingReplacement = nil
        if keepBoth, let folder = destination.url {
            var renamed = settings
            renamed.collisionPolicy = .rename
            run(ExportPlanner().plan(inputs: batch.inputs, settings: renamed, destination: folder), isRetry: false)
        } else {
            run(pending.plan, isRetry: false)
        }
    }

    func retryFailed() {
        guard let session = exportSession, !session.isRunning else { return }
        let ids = Set(session.failedResults.map(\.id))
        guard !ids.isEmpty else { return }
        run(session.plan.restricted(to: ids), isRetry: true)
    }

    func cancelExport() {
        exportSession?.cancel()
    }

    func dismissExport() {
        guard exportSession?.isRunning != true else { return }
        exportSession = nil
    }

    func startAnotherBatch() {
        dismissExport()
        clearQueue()
    }

    func openDestinationInFinder(for session: ExportSession) {
        if let file = session.firstWrittenFile {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(session.plan.destination)
        }
    }

    private func run(_ plan: ExportPlan, isRetry: Bool) {
        let session = ExportSession(plan: plan, isRetry: isRetry)
        exportSession = session
        batch.setPhase(.waiting, for: plan.jobs.map(\.id))

        let exportRun = exporter.start(plan)
        session.attach(exportRun)
        Task {
            for await event in exportRun.events {
                session.apply(event)
                switch event {
                case .jobStarted(let id, _):
                    batch.setPhase(.processing, for: [id])
                case .jobFinished(let id):
                    batch.setPhase(.idle, for: [id])
                    batch.merge(session.resultsByInput[id] ?? [], for: id, replacingAll: !isRetry)
                case .finished:
                    finish(session)
                case .variantFinished:
                    break
                }
            }
        }
    }

    private func finish(_ session: ExportSession) {
        // Jobs that never started (cancelled) still need their final state in the queue.
        for job in session.plan.jobs {
            batch.setPhase(.idle, for: [job.id])
            if let results = session.resultsByInput[job.id] {
                batch.merge(results, for: job.id, replacingAll: !session.isRetry)
            }
        }
        let failures = session.failedResults.compactMap { if case .failed(let f) = $0.outcome { f } else { nil } }
        recentFailures = Array((failures + recentFailures).prefix(50))
        recents.record(RecentExport(
            date: Date(),
            destinationPath: session.plan.destination.path,
            settingsSummary: session.plan.settings.summary,
            summary: session.summary,
            cancelled: session.wasCancelled
        ))
        do {
            try recentsStore.save(recents)
        } catch {
            // History is a convenience; failing to save it must not interrupt the user.
        }
        if NSApp.isActive == false {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }
}
