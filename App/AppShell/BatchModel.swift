import Foundation
import Observation
import PixtamerKit

/// The image queue and its selection.
@MainActor
@Observable
final class BatchModel {
    private(set) var items: [QueueItem] = []
    var selection: Set<QueueItem.ID> = []
    var isImporting = false

    var isEmpty: Bool { items.isEmpty }
    var inputs: [ImageInput] { items.map(\.input) }
    var identityKeys: Set<String> { Set(items.map(\.input.identityKey)) }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.input.fileSize } }

    func item(_ id: QueueItem.ID) -> QueueItem? {
        items.first { $0.id == id }
    }

    func index(of id: QueueItem.ID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    /// Selected items in queue order, or every item when nothing is selected.
    var selectedOrAll: [QueueItem] {
        selection.isEmpty ? items : items.filter { selection.contains($0.id) }
    }

    func add(_ inputs: [ImageInput]) {
        items.append(contentsOf: inputs.map { QueueItem(input: $0) })
    }

    func remove(_ ids: Set<QueueItem.ID>) {
        for item in items where ids.contains(item.id) {
            ThumbnailLoader.shared.evict(item.input.url)
        }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
    }

    func setPhase(_ phase: QueueItem.Phase, for ids: some Sequence<UUID>) {
        let set = Set(ids)
        for index in items.indices where set.contains(items[index].id) {
            items[index].phase = phase
        }
    }

    /// Stores results from a run. Results with the same ID (a retry) replace earlier ones.
    func merge(_ results: [VariantResult], for inputID: UUID, replacingAll: Bool) {
        guard let index = index(of: inputID) else { return }
        if replacingAll {
            items[index].results = results
        } else {
            for result in results {
                if let existing = items[index].results.firstIndex(where: { $0.id == result.id }) {
                    items[index].results[existing] = result
                } else {
                    items[index].results.append(result)
                }
            }
        }
    }
}
