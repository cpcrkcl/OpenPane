//
//  PreviewPanelViewModel.swift
//  OpenPane
//

@preconcurrency import AppKit
import Combine
import Foundation

@MainActor
final class PreviewPanelViewModel: ObservableObject {
    enum PendingTransition: Equatable {
        case select(FilePreviewTarget?)
        case close
    }

    enum UnsavedChangesPrompt: Equatable {
        case transition(PendingTransition)
        case conflict
    }

    @Published private(set) var target: FilePreviewTarget?
    @Published private(set) var metadata: FilePreviewMetadata?
    @Published private(set) var icon: NSImage?
    @Published private(set) var isLoadingMetadata = false
    @Published private(set) var textEditEligibility: TextEditEligibility?
    @Published private(set) var inspectedTextEncoding: TextFileEncoding?
    @Published private(set) var editableDocument: EditableTextDocument?
    @Published private(set) var editorBuffer: PlainTextEditorBuffer?
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var isLoadingText = false
    @Published private(set) var isSaving = false
    @Published private(set) var pendingTransition: PendingTransition?
    @Published private(set) var resolvedCloseRequestCount = 0
    @Published var unsavedChangesPrompt: UnsavedChangesPrompt?
    @Published var errorMessage: String?

    private let metadataService: any FilePreviewMetadataServicing
    private let textEditingService: any TextFileEditingServicing
    private let fileIconService: any FileIconServicing

    private var metadataTask: Task<Void, Never>?
    private var iconTask: Task<Void, Never>?
    private var eligibilityTask: Task<Void, Never>?
    private var textTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var editorBufferCancellable: AnyCancellable?
    private var focusedTargetCancellable: AnyCancellable?
    private var focusedTarget: FilePreviewTarget?
    private var isPanelVisible = true
    private var requestGeneration = 0

    var isEditing: Bool {
        editorBuffer != nil
    }

    var isDirty: Bool {
        hasUnsavedChanges
    }

    var previewRevision: FilePreviewRevision? {
        metadata?.revision
    }

    var canBeginEditing: Bool {
        guard !isEditing,
              !isLoadingText,
              !isSaving else {
            return false
        }
        return textEditEligibility == .eligible
    }

    init(
        metadataService: any FilePreviewMetadataServicing = FilePreviewMetadataService(),
        textEditingService: any TextFileEditingServicing = TextFileEditingService(),
        fileIconService: (any FileIconServicing)? = nil
    ) {
        self.metadataService = metadataService
        self.textEditingService = textEditingService
        self.fileIconService = fileIconService ?? FileIconService.shared
    }

    deinit {
        metadataTask?.cancel()
        iconTask?.cancel()
        eligibilityTask?.cancel()
        textTask?.cancel()
        saveTask?.cancel()
    }

    /// Subscribes the controller directly to the focused item stream so file
    /// navigation updates only the preview subtree, not the whole workspace.
    func bindFocusedTargets(
        to publisher: AnyPublisher<FilePreviewTarget?, Never>,
        isPanelVisible: Bool
    ) {
        self.isPanelVisible = isPanelVisible
        focusedTargetCancellable = publisher.sink { [weak self] target in
            guard let self else { return }
            self.focusedTarget = target
            if self.isPanelVisible {
                self.select(target)
            }
        }
    }

    func setPanelVisible(_ isVisible: Bool) {
        isPanelVisible = isVisible
        if isVisible {
            select(focusedTarget)
        } else if !isDirty {
            select(nil)
        }
    }

    /// Selects a preview target, or defers it while a dirty edit is resolved.
    func select(_ newTarget: FilePreviewTarget?) {
        guard newTarget != target else {
            return
        }

        let transition = PendingTransition.select(newTarget)
        guard !isDirty else {
            pendingTransition = transition
            unsavedChangesPrompt = .transition(transition)
            return
        }

        applySelection(newTarget)
    }

    /// Requests that the panel close. Returns true when it can close now.
    @discardableResult
    func requestClose() -> Bool {
        guard !isDirty else {
            let transition = PendingTransition.close
            pendingTransition = transition
            unsavedChangesPrompt = .transition(transition)
            return false
        }
        return true
    }

    func beginEditing() {
        guard canBeginEditing,
              let metadata else {
            return
        }

        textTask?.cancel()
        isLoadingText = true
        errorMessage = nil
        let generation = requestGeneration
        let url = metadata.url
        let service = textEditingService

        textTask = Task { [weak self] in
            do {
                let document = try await service.load(url: url)
                try Task.checkCancellation()
                guard let self,
                      self.requestGeneration == generation,
                      self.target?.item.url == url else {
                    return
                }
                self.installEditor(for: document)
                self.isLoadingText = false
            } catch is CancellationError {
                guard let self, self.requestGeneration == generation else {
                    return
                }
                self.isLoadingText = false
            } catch {
                guard let self, self.requestGeneration == generation else {
                    return
                }
                self.isLoadingText = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelEditing(force: Bool = false) {
        if isDirty, !force {
            let transition = pendingTransition ?? .select(target)
            pendingTransition = transition
            unsavedChangesPrompt = .transition(transition)
            return
        }

        leaveEditor()
        completePendingTransition()
    }

    func discardChanges() {
        unsavedChangesPrompt = nil
        leaveEditor()
        completePendingTransition()
    }

    func keepEditing() {
        pendingTransition = nil
        unsavedChangesPrompt = nil
    }

    func save(
        overwriteChangedFile: Bool = false,
        onSaved: (@MainActor @Sendable (URL) -> Void)? = nil
    ) {
        guard !isSaving,
              let document = editableDocument,
              let editorBuffer else {
            return
        }

        isSaving = true
        errorMessage = nil
        let text = editorBuffer.stringForSaving
        let service = textEditingService
        let conflictPolicy: TextSaveConflictPolicy = overwriteChangedFile ? .overwrite : .failIfChanged

        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                let savedDocument = try await service.save(
                    document: document,
                    text: text,
                    conflictPolicy: conflictPolicy
                )
                try Task.checkCancellation()
                guard let self else {
                    return
                }
                self.editableDocument = savedDocument
                self.editorBuffer?.markSaved()
                self.metadataService.invalidate(document.url)
                if let target = self.target {
                    self.fileIconService.invalidateIcon(for: target.item)
                }
                self.isSaving = false
                onSaved?(document.url)
                self.leaveEditor()
                if self.pendingTransition == nil {
                    self.reloadCurrentTarget()
                } else {
                    self.completePendingTransition()
                }
            } catch is CancellationError {
                self?.isSaving = false
            } catch TextFileEditingError.fileChanged(_) {
                guard let self else {
                    return
                }
                self.isSaving = false
                self.unsavedChangesPrompt = .conflict
            } catch {
                guard let self else {
                    return
                }
                self.isSaving = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func reloadChangedFile() {
        unsavedChangesPrompt = nil
        leaveEditor()
        if pendingTransition == nil {
            beginEditing()
        } else {
            completePendingTransition()
        }
    }

    func overwriteChangedFile(onSaved: (@MainActor @Sendable (URL) -> Void)? = nil) {
        unsavedChangesPrompt = nil
        save(overwriteChangedFile: true, onSaved: onSaved)
    }

    func cancelPendingWork() {
        requestGeneration &+= 1
        metadataTask?.cancel()
        iconTask?.cancel()
        eligibilityTask?.cancel()
        textTask?.cancel()
        saveTask?.cancel()
        isLoadingMetadata = false
        isLoadingText = false
        isSaving = false
    }

    private func applySelection(_ newTarget: FilePreviewTarget?) {
        requestGeneration &+= 1
        let generation = requestGeneration
        metadataTask?.cancel()
        iconTask?.cancel()
        eligibilityTask?.cancel()
        textTask?.cancel()
        saveTask?.cancel()
        leaveEditor()

        target = newTarget
        metadata = nil
        icon = nil
        textEditEligibility = nil
        inspectedTextEncoding = nil
        errorMessage = nil
        isLoadingText = false
        isSaving = false
        pendingTransition = nil
        unsavedChangesPrompt = nil

        guard let newTarget else {
            isLoadingMetadata = false
            return
        }

        isLoadingMetadata = true
        let metadataService = metadataService
        metadataTask = Task { [weak self] in
            do {
                let metadata = try await metadataService.metadata(for: newTarget.item.url)
                try Task.checkCancellation()
                guard let self,
                      self.requestGeneration == generation,
                      self.target?.id == newTarget.id else {
                    return
                }
                self.metadata = metadata
                self.isLoadingMetadata = false

                let enrichedMetadata = try await metadataService.enrichedMetadata(for: metadata)
                try Task.checkCancellation()
                guard self.requestGeneration == generation,
                      self.target?.id == newTarget.id else {
                    return
                }
                self.metadata = enrichedMetadata
            } catch is CancellationError {
                guard let self, self.requestGeneration == generation else {
                    return
                }
                self.isLoadingMetadata = false
            } catch {
                guard let self,
                      self.requestGeneration == generation,
                      self.target?.id == newTarget.id else {
                    return
                }
                self.isLoadingMetadata = false
                self.errorMessage = error.localizedDescription
            }
        }

        let iconService = fileIconService
        iconTask = Task { [weak self] in
            let icon = await iconService.icon(for: newTarget.item)
            guard !Task.isCancelled,
                  let self,
                  self.requestGeneration == generation,
                  self.target?.id == newTarget.id else {
                return
            }
            self.icon = icon
        }

        let textEditingService = textEditingService
        eligibilityTask = Task { [weak self] in
            let eligibility = await textEditingService.inspect(url: newTarget.item.url)
            guard !Task.isCancelled,
                  let self,
                  self.requestGeneration == generation,
                  self.target?.id == newTarget.id else {
                return
            }
            self.textEditEligibility = eligibility
        }
    }

    private func installEditor(for document: EditableTextDocument) {
        editableDocument = document
        inspectedTextEncoding = document.encoding
        let buffer = PlainTextEditorBuffer(text: document.text)
        editorBuffer = buffer
        editorBufferCancellable = buffer.$isDirty
            .sink { [weak self] isDirty in
                self?.hasUnsavedChanges = isDirty
            }
    }

    private func leaveEditor() {
        editorBufferCancellable = nil
        editorBuffer = nil
        editableDocument = nil
        hasUnsavedChanges = false
        isLoadingText = false
    }

    private func completePendingTransition() {
        let transition = pendingTransition
        pendingTransition = nil
        unsavedChangesPrompt = nil
        guard let transition else {
            return
        }
        switch transition {
        case .select(let target):
            applySelection(target)
        case .close:
            resolvedCloseRequestCount &+= 1
        }
    }

    private func reloadCurrentTarget() {
        guard let target else {
            return
        }
        applySelection(target)
    }
}

/// Coordinates dirty state with window-close and application-termination
/// callers without teaching those callers about editor implementation details.
/// A false result means the close is deferred until the user resolves the
/// prompt; the completion runs only when a previously deferred close is later
/// resolved by a successful Save or Discard.
@MainActor
final class PreviewEditSessionCoordinator: ObservableObject {
    @Published private(set) var isDirty = false

    private weak var viewModel: PreviewPanelViewModel?
    private var cancellables: Set<AnyCancellable> = []
    private var deferredCloseCompletion: (() -> Void)?
    private var deferredCloseCancellation: (() -> Void)?

    init(viewModel: PreviewPanelViewModel? = nil) {
        if let viewModel {
            bind(to: viewModel)
        }
    }

    func bind(to viewModel: PreviewPanelViewModel) {
        self.viewModel = viewModel
        cancellables.removeAll()

        viewModel.$hasUnsavedChanges
            .removeDuplicates()
            .sink { [weak self] isDirty in
                self?.isDirty = isDirty
            }
            .store(in: &cancellables)

        viewModel.$resolvedCloseRequestCount
            .dropFirst()
            .sink { [weak self] _ in
                let completion = self?.deferredCloseCompletion
                self?.deferredCloseCompletion = nil
                self?.deferredCloseCancellation = nil
                completion?()
            }
            .store(in: &cancellables)
    }

    @discardableResult
    func requestClose(
        onDeferredResolution: @escaping () -> Void,
        onCancelled: @escaping () -> Void = {}
    ) -> Bool {
        guard let viewModel else {
            return true
        }

        if viewModel.requestClose() {
            return true
        }

        deferredCloseCompletion = onDeferredResolution
        deferredCloseCancellation = onCancelled
        return false
    }

    func cancelDeferredClose() {
        let cancellation = deferredCloseCancellation
        deferredCloseCompletion = nil
        deferredCloseCancellation = nil
        viewModel?.keepEditing()
        cancellation?()
    }
}
