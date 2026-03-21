import SwiftUI

struct TreatSessionView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator
    @EnvironmentObject private var vm: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    // =========================================================
    // MARK: - Sheet routing (single sheet fixes iPad focus)
    // =========================================================

    private enum SheetRoute: Identifiable {
        case add(id: UUID)
        case edit(SessionTreatment)

        var id: UUID {
            switch self {
            case .add(let id): return id
            case .edit(let t): return t.id
            }
        }
    }

    @State private var sheet: SheetRoute? = nil
    @State private var isEditMode: Bool = false

    // Form fields (used for add + edit)
    @State private var product: String = ""
    @State private var dosage: String = ""
    @State private var withholding: String = ""

    private var sessionID: UUID? { coordinator.activeSessionID }

    private var treatments: [SessionTreatment] {
        guard let id = sessionID else { return [] }
        return store.treatments(for: id)
    }

    private var canSave: Bool {
        !product.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    headerCard

                    if sessionID == nil {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No Active Session")
                                    .font(.headline)
                                Text("Go to the Session tab and start/select a session first.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if treatments.isEmpty {
                        emptyAddCard
                    } else {
                        addRowCard
                        treatmentsList
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
                .safeAreaPadding(.top, 10)
            }
        }
        // ✅ Single sheet presenter prevents focus/caret flashing on iPad
        .sheet(item: $sheet, onDismiss: resetForm) { route in
            switch route {
            case .add:
                addEditSheet(title: "Add Treatment", isEditing: false)
            case .edit:
                addEditSheet(title: "Edit Treatment", isEditing: true)
            }
        }
        .onChange(of: sessionID) { _, _ in
            // If session changes while open, reset edit state.
            isEditMode = false
            sheet = nil
            resetForm()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Treatments")
                        .font(.title3.weight(.bold))

                    if sessionID != nil {
                        Text("Attached to this session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No active session selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if sessionID != nil, !treatments.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            isEditMode.toggle()
                        }
                    } label: {
                        Label(
                            isEditMode ? "Done" : "Edit",
                            systemImage: isEditMode ? "checkmark.circle.fill" : "pencil"
                        )
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty state add card

    private var emptyAddCard: some View {
        Button {
            beginAdd()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 46, weight: .bold))

                Text("Add Treatment")
                    .font(.headline)

                Text("Tap to create a treatment for this session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Add row (when list exists)

    private var addRowCard: some View {
        Button {
            beginAdd()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2.weight(.bold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Treatment")
                        .font(.headline)
                    Text("Attach to every animal in this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Treatments list

    private var treatmentsList: some View {
        VStack(spacing: 12) {
            ForEach(treatments) { t in
                GlassCard {
                    HStack(alignment: .top, spacing: 12) {

                        // Big tap target to edit (no nested Button conflicts)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.product)
                                .font(.headline)

                            Text(summaryLine(for: t))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            beginEdit(t)
                        }

                        // Delete only in edit mode (bigger + glove friendly)
                        if isEditMode {
                            Button(role: .destructive) {
                                deleteTreatment(t)
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.headline.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(
                                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete treatment")
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sheet

    @ViewBuilder
    private func addEditSheet(title: String, isEditing: Bool) -> some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {

                                fieldLabel("Product")
                                TextField("e.g. Cydectin", text: $product)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)

                                Divider().opacity(0.25)

                                fieldLabel("Dosage")
                                TextField("e.g. 3.4 mL", text: $dosage)
                                    .textFieldStyle(.roundedBorder)

                                Divider().opacity(0.25)

                                fieldLabel("Withholding (optional)")
                                TextField("e.g. 14 days", text: $withholding)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        // Glove-friendly actions in edit sheet
                        if isEditing {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Danger Zone")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    Button(role: .destructive) {
                                        if case .edit(let t) = sheet {
                                            deleteTreatment(t)
                                        }
                                        dismissSheet()
                                        resetForm()
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "trash.fill")
                                            Text("Remove from Session")
                                                .font(.headline.weight(.semibold))
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(16)
                    .safeAreaPadding(.top, 10)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismissSheet() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveTreatment(isEditing: isEditing)
                    }
                    .disabled(!canSave || sessionID == nil)
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func dismissSheet() {
        sheet = nil
    }

    // MARK: - Actions

    private func beginAdd() {
        resetForm()
        sheet = .add(id: UUID())
    }

    private func beginEdit(_ t: SessionTreatment) {
        product = t.product
        dosage = t.dosage
        withholding = t.withholding
        sheet = .edit(t)
    }

    private func deleteTreatment(_ t: SessionTreatment) {
        guard let sid = sessionID else { return }
        store.deleteTreatment(sessionID: sid, treatmentID: t.id)

        // If you delete the one you're editing, pop the sheet.
        if case .edit(let current) = sheet, current.id == t.id {
            sheet = nil
        }

        // If list is now empty, drop edit mode.
        if treatments.count <= 1 {
            isEditMode = false
        }
    }

    private func saveTreatment(isEditing: Bool) {
        guard let sid = sessionID else { return }

        let p = product.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = withholding.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !p.isEmpty, !d.isEmpty else { return }

        if isEditing, case .edit(let existing) = sheet {
            let updated = SessionTreatment(
                id: existing.id,
                product: p,
                dosage: d,
                withholding: w
            )
            store.updateTreatment(sessionID: sid, treatment: updated)
        } else {
            store.addTreatment(sessionID: sid, product: p, dosage: d, withholding: w)
        }

        vm.reloadSessionTreatments()
        vm.markTreatmentCompleted()

        dismissSheet()
        resetForm()
    }

    private func resetForm() {
        product = ""
        dosage = ""
        withholding = ""
    }

    private func summaryLine(for t: SessionTreatment) -> String {
        let d = t.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = t.withholding.trimmingCharacters(in: .whitespacesAndNewlines)

        if w.isEmpty { return d }
        if d.isEmpty { return w }
        return "\(d) • \(w)"
    }
}
