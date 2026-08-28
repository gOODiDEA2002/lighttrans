import Foundation

private actor SerialEventEmitter {
    private let emit: @Sendable (TranslationEvent) async -> Void

    init(emit: @escaping @Sendable (TranslationEvent) async -> Void) {
        self.emit = emit
    }

    func send(_ event: TranslationEvent) async {
        await emit(event)
    }
}

public struct TranslationWorkflow: Sendable {
    private let configurationProvider: any TranslationConfigurationProviding
    private let historyStore: ProcessSafeHistoryStore
    private let now: @Sendable () -> Date
    private let loadDeviceName: @Sendable () -> String
    private let translateStream: @Sendable (TranslationRoute, TranslationRequest, TranslationConfigurationSnapshot, ModelRequestConfiguration) -> AsyncThrowingStream<String, Error>

    public init(
        configurationProvider: any TranslationConfigurationProviding = SharedConfigurationProvider(),
        translationService: TranslationService = TranslationService(),
        historyStore: ProcessSafeHistoryStore = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        loadDeviceName: @escaping @Sendable () -> String = { Host.current().localizedName ?? "未知设备" },
        translateStream: (@Sendable (TranslationRoute, TranslationRequest, TranslationConfigurationSnapshot, ModelRequestConfiguration) -> AsyncThrowingStream<String, Error>)? = nil
    ) {
        self.configurationProvider = configurationProvider
        self.historyStore = historyStore
        self.now = now
        self.loadDeviceName = loadDeviceName
        if let translateStream {
            self.translateStream = translateStream
        } else {
            self.translateStream = { route, request, snapshot, configuration in
                translationService.translate(
                    text: request.text,
                    template: route == .literal ? snapshot.literalTemplate : snapshot.rewriteTemplate,
                    configuration: configuration
                )
            }
        }
    }

    public func run(
        request: TranslationRequest,
        emit: @escaping @Sendable (TranslationEvent) async -> Void
    ) async -> TranslationSummary {
        let emitter = SerialEventEmitter(emit: emit)
        var snapshot: TranslationConfigurationSnapshot?
        var snapshotError: TranslationError?

        do {
            snapshot = try configurationProvider.loadRequestSnapshot()
        } catch is ConfigurationProviderError {
            snapshotError = .configurationUnavailable
        } catch {
            snapshotError = .configurationUnavailable
        }

        await emitter.send(.started(mode: request.mode, model: snapshot?.modelName ?? ""))

        let routes = request.mode.routes
        var routeSummaries: [TranslationRoute: TranslationRouteSummary] = [:]

        if let snapshotError {
            for route in routes {
                routeSummaries[route] = TranslationRouteSummary(
                    route: route,
                    status: .failed,
                    text: "",
                    failure: snapshotError.failure
                )
                await emitter.send(.routeFinished(routeSummaries[route]!))
            }
            return await finish(
                request: request,
                emitter: emitter,
                routeSummaries: routeSummaries,
                forcedCancelled: Task.isCancelled,
                modelName: snapshot?.modelName ?? "",
                snapshot: snapshot
            )
        }

        guard let validSnapshot = snapshot else {
            for route in routes {
                let summary = TranslationRouteSummary(
                    route: route,
                    status: .failed,
                    text: "",
                    failure: TranslationError.configurationUnavailable.failure
                )
                routeSummaries[route] = summary
                await emitter.send(.routeFinished(summary))
            }
            return await finish(
                request: request,
                emitter: emitter,
                routeSummaries: routeSummaries,
                forcedCancelled: Task.isCancelled,
                modelName: "",
                snapshot: snapshot
            )
        }

        let configuration: ModelRequestConfiguration
        do {
            configuration = try makeModelConfiguration(from: validSnapshot)
        } catch let error as TranslationError {
            for route in routes {
                let summary = TranslationRouteSummary(
                    route: route,
                    status: .failed,
                    text: "",
                    failure: error.failure
                )
                routeSummaries[route] = summary
                await emitter.send(.routeFinished(summary))
            }
            return await finish(
                request: request,
                emitter: emitter,
                routeSummaries: routeSummaries,
                forcedCancelled: Task.isCancelled,
                modelName: validSnapshot.modelName,
                snapshot: validSnapshot
            )
        } catch {
            for route in routes {
                let summary = TranslationRouteSummary(
                    route: route,
                    status: .failed,
                    text: "",
                    failure: TranslationError.badResponse(error.localizedDescription).failure
                )
                routeSummaries[route] = summary
                await emitter.send(.routeFinished(summary))
            }
            return await finish(
                request: request,
                emitter: emitter,
                routeSummaries: routeSummaries,
                forcedCancelled: Task.isCancelled,
                modelName: validSnapshot.modelName,
                snapshot: validSnapshot
            )
        }

        await withTaskGroup(of: TranslationRouteSummary.self) { group in
            for route in routes {
                group.addTask {
                    await runRoute(
                        route: route,
                        request: request,
                        snapshot: validSnapshot,
                        configuration: configuration,
                        emitter: emitter
                    )
                }
            }

            for await summary in group {
                routeSummaries[summary.route] = summary
                await emitter.send(.routeFinished(summary))
            }
        }

        return await finish(
            request: request,
            emitter: emitter,
            routeSummaries: routeSummaries,
            forcedCancelled: Task.isCancelled,
            modelName: validSnapshot.modelName,
            snapshot: validSnapshot
        )
    }

    private func makeModelConfiguration(from snapshot: TranslationConfigurationSnapshot) throws -> ModelRequestConfiguration {
        let apiBaseURL = snapshot.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = snapshot.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (snapshot.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiBaseURL.isEmpty, !modelName.isEmpty, !apiKey.isEmpty else {
            throw TranslationError.notConfigured
        }
        guard snapshot.maxTokens > 0 else {
            throw TranslationError.notConfigured
        }
        return ModelRequestConfiguration(
            apiBaseURL: apiBaseURL,
            modelName: modelName,
            apiKey: apiKey,
            maxTokens: snapshot.maxTokens
        )
    }

    private func runRoute(
        route: TranslationRoute,
        request: TranslationRequest,
        snapshot: TranslationConfigurationSnapshot,
        configuration: ModelRequestConfiguration,
        emitter: SerialEventEmitter
    ) async -> TranslationRouteSummary {
        var output = ""
        do {
            for try await chunk in translateStream(route, request, snapshot, configuration) {
                output += chunk
                await emitter.send(.chunk(route: route, text: chunk))
            }
            let status: TranslationRouteStatus = Task.isCancelled ? .stopped : .done
            return TranslationRouteSummary(route: route, status: status, text: output, failure: nil)
        } catch is CancellationError {
            return TranslationRouteSummary(route: route, status: .stopped, text: output, failure: nil)
        } catch let error as TranslationError {
            let status: TranslationRouteStatus = Task.isCancelled ? .stopped : .failed
            let failure = status == .failed ? error.failure : nil
            return TranslationRouteSummary(route: route, status: status, text: output, failure: failure)
        } catch {
            let status: TranslationRouteStatus = Task.isCancelled ? .stopped : .failed
            let unknown = TranslationError.badResponse(error.localizedDescription).failure
            return TranslationRouteSummary(
                route: route,
                status: status,
                text: output,
                failure: status == .failed ? unknown : nil
            )
        }
    }

    private func finish(
        request: TranslationRequest,
        emitter: SerialEventEmitter,
        routeSummaries: [TranslationRoute: TranslationRouteSummary],
        forcedCancelled: Bool,
        modelName: String,
        snapshot: TranslationConfigurationSnapshot?
    ) async -> TranslationSummary {
        let status = aggregateStatus(
            routes: request.mode.routes,
            routeSummaries: routeSummaries,
            forcedCancelled: forcedCancelled
        )
        let summary = TranslationSummary(
            mode: request.mode,
            status: status,
            model: modelName,
            literal: routeSummaries[.literal],
            rewrite: routeSummaries[.rewrite],
            history: .disabled
        )

        let historyEnabled = configurationProvider.isHistoryEnabled()
        let historyOutcome: HistoryWriteOutcome
        if historyEnabled {
            let record = buildHistoryRecord(request: request, summary: summary)
            historyOutcome = await historyStore.append(record)
        } else {
            historyOutcome = .disabled
        }

        let finalSummary = TranslationSummary(
            mode: summary.mode,
            status: summary.status,
            model: summary.model,
            literal: summary.literal,
            rewrite: summary.rewrite,
            history: historyOutcome
        )
        await emitter.send(.finished(finalSummary))
        return finalSummary
    }

    private func aggregateStatus(
        routes: [TranslationRoute],
        routeSummaries: [TranslationRoute: TranslationRouteSummary],
        forcedCancelled: Bool
    ) -> TranslationStatus {
        if forcedCancelled {
            return .stopped
        }
        let summaries = routes.compactMap { routeSummaries[$0] }
        if summaries.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if summaries.contains(where: { $0.status == .stopped }) {
            return .stopped
        }
        return .done
    }

    private func buildHistoryRecord(request: TranslationRequest, summary: TranslationSummary) -> HistoryRecord {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current

        let errors: [String] = [summary.literal?.failure?.message, summary.rewrite?.failure?.message].compactMap { $0 }
        let error = errors.isEmpty ? nil : errors.joined(separator: "；")
        return HistoryRecord(
            id: UUID().uuidString,
            time: formatter.string(from: now()),
            device: loadDeviceName(),
            model: summary.model,
            status: summary.status.rawValue,
            input: request.text,
            mode: summary.mode,
            output: nil,
            literalOutput: summary.literal?.text,
            rewriteOutput: summary.rewrite?.text,
            error: summary.status == .failed ? error : nil
        )
    }
}
