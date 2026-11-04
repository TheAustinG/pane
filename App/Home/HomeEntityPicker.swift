import PaneCore
import SwiftUI

/// Chooses the entities for one role. Laid out like the Settings choice screens: title and help on
/// the left, the candidates in a 1000 pt list on the right.
struct HomeEntityPicker: View {
    let model: AppModel
    let role: HomeEntityRole
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: String?

    private static let noneID = "none"

    private var selected: [String] { model.home.selection.entityIDs(for: role) }
    private var candidates: [HAEntity] { role.candidates(in: model.home.entities.values) }

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(role.title)
                    .font(Theme.Typeface.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                SettingsHelpPane(text: role.help)
            }
            .frame(width: 620, alignment: .leading)
            List {
                if !role.allowsMany {
                    row(id: Self.noneID, title: "None", detail: nil, isSelected: selected.isEmpty) {
                        update([])
                        dismiss()
                    }
                }
                ForEach(candidates) { entity in
                    row(id: entity.entityID, title: entity.friendlyName, detail: entity.stateText, isSelected: selected.contains(entity.entityID)) {
                        choose(entity.entityID)
                    }
                }
                if candidates.isEmpty {
                    Text("No matching entities found")
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.Ink.tertiary)
                        .accessibilityIdentifier("home.picker.empty")
                }
            }
            .frame(width: 1000)
            .accessibilityIdentifier("home.picker.\(role.rawValue)")
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
        .defaultFocus($focused, selected.first(where: { id in candidates.contains { $0.entityID == id } }) ?? candidates.first?.entityID ?? Self.noneID)
    }

    private func row(id: String, title: String, detail: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                Text(title).lineLimit(1)
                Spacer(minLength: Theme.Space.m)
                if let detail {
                    Text(detail).foregroundStyle(.secondary).lineLimit(1)
                }
                Image(systemName: "checkmark")
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .focused($focused, equals: id)
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityIdentifier("home.picker.row.\(id)")
    }

    private func choose(_ id: String) {
        if role.allowsMany {
            var ids = selected
            if let index = ids.firstIndex(of: id) { ids.remove(at: index) } else { ids.append(id) }
            update(ids)
        } else {
            update([id])
            dismiss()
        }
    }

    private func update(_ ids: [String]) {
        model.home.selection.setEntityIDs(ids, for: role)
    }
}
