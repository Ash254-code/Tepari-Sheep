import SwiftUI

/// Treatments-only step
struct SessionSetupTreatmentsStepView: View {

    // =========================================================
    // MARK: - Tepari dosing gun
    // =========================================================

    /// Stored in SessionConfig.tepariGunEnabled
    @Binding var tepariGunEnabled: Bool

    /// Treatment assigned to the Tepari gun.
    /// Tepari can only be linked to one treatment even if multiple treatments are selected.
    @Binding var tepariTreatmentID: UUID?

    /// Parent decides what "enable" means (turn on G pill, prompt connection, etc.)
    let onTepariChanged: (Bool) -> Void

    // =========================================================
    // MARK: - Treatments
    // =========================================================

    @Binding var recordTreatments: Bool
    let treatmentLibrary: [TreatmentTemplate]
    @Binding var selectedTreatmentIDs: Set<UUID>
    @Binding var doseOverrides: [UUID: DoseValue]
    let onAddTreatmentTemplate: (TreatmentTemplate) -> Void
    let onSelectionChanged: () -> Void

    // =========================================================
    // MARK: - Sheet UI
    // =========================================================

    @State private var showAddNewTreatmentSheet: Bool = false
    @State private var newProduct: String = ""
    @State private var newDoseValue: String = ""
    @State private var newDoseUnit: DoseUnit = .mL
    @State private var newDoseBasis: DoseBasis? = nil
    @State private var newDosePerKg: String = "10"
    @State private var newWithholding: String = ""

    private var requiredDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetSectionHeader(
                step: "1",
                title: "Required details",
                subtitle: "These fields are needed before you can save the treatment."
            )

            VStack(spacing: 12) {
                fieldCard(
                    title: "Product",
                    required: true,
                    isValid: productIsValid
                ) {
                    TextField("e.g. Cydectin", text: $newProduct)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                fieldCard(
                    title: "Dose",
                    required: true,
                    isValid: doseIsValid
                ) {
                    HStack(spacing: 0) {
                        TextField("e.g. 3.4", text: $newDoseValue)
    #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
    #endif
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()
                            .frame(height: 24)
                            .padding(.horizontal, 10)

                        Picker("Unit", selection: $newDoseUnit) {
                            ForEach(DoseUnit.allCases, id: \.self) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(minWidth: 70, alignment: .trailing)
                    }
                    .frame(height: 44)
                }
            }
        }
    }

    private var dosingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetSectionHeader(
                step: "2",
                title: "Dose method",
                subtitle: "Flat rate Per animal or adjusted by Per bodyweight",
                isValid: doseBasisIsValid,
                required: true
            )

            VStack(alignment: .leading, spacing: 14) {
                Text("Dose basis")
                    .font(.subheadline.weight(.semibold))

                Picker("Dose basis", selection: Binding<DoseBasis?>(
                    get: { newDoseBasis },
                    set: { newDoseBasis = $0 }
                )) {
                    Text("Per animal").tag(DoseBasis?.some(.perAnimal))
                    Text("Per body weight").tag(DoseBasis?.some(.perBodyWeight))
                }
                .pickerStyle(.segmented)
                .tint(.blue)
                .disabled(newDoseValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if newDoseBasis == .perBodyWeight,
                   !newDoseValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fieldCard(
                        title: "Per kg value",
                        required: true,
                        isValid: perKgIsValid
                    ) {
                        HStack(spacing: 10) {
                            TextField("10", text: $newDosePerKg)
    #if os(iOS)
                                .keyboardType(.numbersAndPunctuation)
    #endif
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Text("kg")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private var withholdingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetSectionHeader(
                step: "3",
                title: "Withholding",
                subtitle: "Optional",
                isValid: !newWithholding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                required: false
            )

            fieldCard(
                title: "Withholding",
                required: false,
                isValid: !newWithholding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                TextField("e.g. 14 days meat WHP", text: $newWithholding)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
            }
        }
    }
    private var canCreateNewTemplate: Bool {
        productIsValid && doseIsValid && doseBasisIsValid && perKgIsValid
    }

    private var selectedTemplates: [TreatmentTemplate] {
        let set = selectedTreatmentIDs
        return treatmentLibrary
            .filter { set.contains($0.id) }
            .sorted { $0.product.localizedCaseInsensitiveCompare($1.product) == .orderedAscending }
    }

    private var filteredLibrary: [TreatmentTemplate] {
        treatmentLibrary.sorted {
            $0.product.localizedCaseInsensitiveCompare($1.product) == .orderedAscending
        }
    }

    private var draftSummaryText: String {
        let product = newProduct.trimmingCharacters(in: .whitespacesAndNewlines)
        let dose = newDoseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withholding = newWithholding.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !product.isEmpty || !dose.isEmpty else { return "Fill in the treatment details below." }

        var parts: [String] = []

        if !product.isEmpty {
            parts.append(product)
        }

        if !dose.isEmpty, let basis = newDoseBasis {
            switch basis {
            case .perAnimal:
                parts.append("\(dose) \(newDoseUnit.rawValue) per animal")
            case .perBodyWeight:
                let per = newDosePerKg.trimmingCharacters(in: .whitespacesAndNewlines)
                let perText = per.isEmpty ? "10" : per
                parts.append("\(dose) \(newDoseUnit.rawValue) / \(perText) kg")
            }
        }

        if !withholding.isEmpty {
            parts.append("WHP: \(withholding)")
        }

        return parts.joined(separator: " • ")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                treatmentsCard
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showAddNewTreatmentSheet) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        requiredDetailsSection
                        dosingSection
                        withholdingSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Add Treatment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showAddNewTreatmentSheet = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addNewTreatmentNow() }
                            .disabled(!canCreateNewTemplate)
                    }
                }
            }
            .presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            seedOverridesIfNeeded()
            pruneOverridesForUnselected()
            syncDerivedState()
        }
        .onChange(of: selectedTreatmentIDs) { _, _ in
            seedOverridesIfNeeded()
            pruneOverridesForUnselected()
            syncDerivedState()
        }
    }

    // =========================================================
    // MARK: Treatments card
    // =========================================================

    private var treatmentsCard: some View {
        stepCard(
            title: "Session Treatments",
            subtitle: "Add treatments for this session. Tepari can be assigned to one selected treatment."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                actionButtonsRow
                librarySection

                if selectedTemplates.isEmpty {
                    emptyStateCard(
                        icon: "cross.case",
                        title: "No treatments selected",
                        subtitle: "Tap treatments from the library to add them to this session."
                    )
                } else {
                    selectedTreatmentsSection
                }
            }
        }
    }

    // =========================================================
    // MARK: Selected treatments
    // =========================================================

    private var selectedTreatmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Selected Treatments",
                subtitle: "Adjust dose here. Turn Tepari on for one treatment only."
            )

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 420), spacing: 12, alignment: .top)
                ],
                spacing: 12
            ) {
                ForEach(selectedTemplates) { t in
                    selectedTreatmentCard(t, isTepariAssigned: tepariTreatmentID == t.id)
                }
            }
        }
    }

    private func selectedTreatmentCard(_ t: TreatmentTemplate, isTepariAssigned: Bool) -> some View {
        let valueBinding = Binding<String>(
            get: {
                let override = doseOverrides[t.id]
                let v = override?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !v.isEmpty { return v }
                return t.doseValue
            },
            set: { newValue in
                var ov = existingOrSeededOverride(for: t)
                ov.value = sanitizedNumericString(newValue)
                doseOverrides[t.id] = ov
                onSelectionChanged()
            }
        )

        let unitBinding = Binding<DoseUnit>(
            get: { doseOverrides[t.id]?.unit ?? t.doseUnit },
            set: { newUnit in
                var ov = existingOrSeededOverride(for: t)
                ov.unit = newUnit
                doseOverrides[t.id] = ov
                onSelectionChanged()
            }
        )

        let basisBinding = Binding<DoseBasis>(
            get: { doseOverrides[t.id]?.basis ?? t.doseBasis },
            set: { newBasis in
                var ov = existingOrSeededOverride(for: t)
                ov.basis = newBasis
                if newBasis == .perAnimal {
                    ov.perKg = nil
                } else {
                    let current = ov.perKg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    ov.perKg = current.isEmpty ? "10" : current
                }
                doseOverrides[t.id] = ov
                onSelectionChanged()
            }
        )

        let perKgBinding = Binding<String>(
            get: {
                let override = doseOverrides[t.id]
                let per = override?.perKg?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let per, !per.isEmpty { return per }

                let base = t.dosePerKg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return base.isEmpty ? "10" : base
            },
            set: { newValue in
                var ov = existingOrSeededOverride(for: t)
                ov.perKg = sanitizedNumericString(newValue)
                doseOverrides[t.id] = ov
                onSelectionChanged()
            }
        )

        let tepariBinding = Binding<Bool>(
            get: { tepariGunEnabled && tepariTreatmentID == t.id },
            set: { newValue in
                if newValue {
                    tepariTreatmentID = t.id
                    tepariGunEnabled = true
                    onTepariChanged(true)
                } else {
                    if tepariTreatmentID == t.id {
                        tepariTreatmentID = nil
                    }
                    tepariGunEnabled = false
                    onTepariChanged(false)
                }
                onSelectionChanged()
            }
        )

        let effectiveBasis = basisBinding.wrappedValue
        let preview = overrideSummary(for: t)

        return VStack(alignment: .leading, spacing: 14) {

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(t.product)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)

                        if isTepariAssigned {
                            tagPill(title: "TEPARI", systemImage: "dot.radiowaves.left.and.right")
                        }
                    }

                    if !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Menu {
                    Button(role: .destructive) {
                        removeTreatment(t)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use Tepari")
                        .font(.subheadline.weight(.semibold))

                    Text(isTepariAssigned ? "Assigned to this treatment" : "Only one treatment can use Tepari")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: tepariBinding)
                    .labelsHidden()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Dose")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button {
                        adjustDose(for: t, delta: -doseStep(for: unitBinding.wrappedValue))
                    } label: {
                        Image(systemName: "minus")
                            .font(.title2.weight(.bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.plain)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))

                    HStack(spacing: 10) {
                        TextField("0", text: valueBinding)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )

                        Picker("Unit", selection: unitBinding) {
                            ForEach(DoseUnit.allCases, id: \.self) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.title3.weight(.semibold))
                    }

                    Button {
                        adjustDose(for: t, delta: doseStep(for: unitBinding.wrappedValue))
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.plain)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                }

                HStack(spacing: 8) {
                    quickDoseButton(title: "-1", action: { adjustDose(for: t, delta: -1) })
                    quickDoseButton(title: "-0.1", action: { adjustDose(for: t, delta: -0.1) })
                    quickDoseButton(title: "+0.1", action: { adjustDose(for: t, delta: 0.1) })
                    quickDoseButton(title: "+1", action: { adjustDose(for: t, delta: 1) })
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Basis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Dose basis", selection: basisBinding) {
                        ForEach(DoseBasis.allCases, id: \.self) { basis in
                            Text(basis.label).tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if effectiveBasis == .perBodyWeight {
                    HStack(spacing: 10) {
                        Text("Per")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Button {
                            adjustPerKg(for: t, delta: -1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.headline.weight(.bold))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))

                        TextField("10", text: perKgBinding)
                            .multilineTextAlignment(.center)
                            .font(.title3.weight(.bold))
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .frame(width: 110)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )

                        Button {
                            adjustPerKg(for: t, delta: 1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.bold))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))

                        Text("kg")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardStroke)
    }

    private func quickDoseButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 10) {
            Button {
                resetNewTreatmentDraft()
                showAddNewTreatmentSheet = true
            } label: {
                Label("Add Treatment", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .glassButton(.compact)

            if !selectedTreatmentIDs.isEmpty {
                Button(role: .destructive) {
                    selectedTreatmentIDs.removeAll()
                    doseOverrides.removeAll()
                    tepariTreatmentID = nil
                    tepariGunEnabled = false
                    recordTreatments = false
                    onTepariChanged(false)
                    onSelectionChanged()
                } label: {
                    Label("Clear All", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .glassButton(.compact)
            }
        }
    }

    // =========================================================
    // MARK: Library
    // =========================================================

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Treatment Library",
                subtitle: "Tap to add or remove saved treatments."
            )

            LazyVStack(spacing: 8) {
                ForEach(filteredLibrary) { t in
                    treatmentRow(t)
                }
            }
        }
    }

    private func treatmentRow(_ t: TreatmentTemplate) -> some View {
        let isOn = selectedTreatmentIDs.contains(t.id)
        let isTepari = tepariGunEnabled && tepariTreatmentID == t.id

        return Button {
            if isOn {
                removeTreatment(t)
            } else {
                selectedTreatmentIDs.insert(t.id)
                seedOverrideIfNeeded(for: t)
                syncDerivedState()
                onSelectionChanged()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.blue : Color.secondary.opacity(0.7))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(t.product)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isTepari {
                            tagPill(title: "TEPARI", systemImage: "dot.radiowaves.left.and.right")
                        }
                    }

                    let detail = summaryLine(template: t)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isOn ? 0.18 : 0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // =========================================================
    // MARK: Add Treatment Sheet
    // =========================================================

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetSectionHeader(
                step: "3",
                title: "Optional",
                subtitle: "Add any extra detail you want to save with this treatment."
            )

            fieldCard(
                title: "Withholding",
                subtitle: "Optional note",
                required: false,
                isValid: true
            ) {
                TextField("e.g. 14 days meat WHP", text: $newWithholding)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
            }
        }
    }

    private func addNewTreatmentNow() {
        guard canCreateNewTemplate else { return }

        let created = TreatmentTemplate(
            id: UUID(),
            product: newProduct,
            doseValue: newDoseValue,
            doseUnit: newDoseUnit,
            doseBasis: newDoseBasis ?? .perAnimal,
            dosePerKg: newDoseBasis == .perBodyWeight ? newDosePerKg : nil,
            withholding: newWithholding
        )

        onAddTreatmentTemplate(created)
        selectedTreatmentIDs.insert(created.id)

        let base = created.doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty {
            doseOverrides[created.id] = DoseValue(
                value: base,
                unit: created.doseUnit,
                basis: created.doseBasis,
                perKg: created.doseBasis == .perBodyWeight ? created.dosePerKg : nil
            )
        }

        syncDerivedState()
        onSelectionChanged()
        showAddNewTreatmentSheet = false
        resetNewTreatmentDraft()
    }
    private var productIsValid: Bool {
        !newProduct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var doseIsValid: Bool {
        !newDoseValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var doseBasisIsValid: Bool {
        newDoseBasis != nil
    }

    private var perKgIsValid: Bool {
        newDoseBasis == .perAnimal || !newDosePerKg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // =========================================================
    // MARK: Override seeding
    // =========================================================

    private func seedOverridesIfNeeded() {
        guard !selectedTemplates.isEmpty else { return }
        for t in selectedTemplates {
            seedOverrideIfNeeded(for: t)
        }
    }

    private func seedOverrideIfNeeded(for t: TreatmentTemplate) {
        if doseOverrides[t.id] == nil {
            let base = t.doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.isEmpty {
                doseOverrides[t.id] = DoseValue(
                    value: base,
                    unit: t.doseUnit,
                    basis: t.doseBasis,
                    perKg: t.doseBasis == .perBodyWeight ? t.dosePerKg : nil
                )
            }
        }
    }

    private func existingOrSeededOverride(for t: TreatmentTemplate) -> DoseValue {
        if let existing = doseOverrides[t.id] {
            return existing
        }

        return DoseValue(
            value: t.doseValue,
            unit: t.doseUnit,
            basis: t.doseBasis,
            perKg: t.doseBasis == .perBodyWeight ? t.dosePerKg : nil
        )
    }

    private func pruneOverridesForUnselected() {
        let allowed = selectedTreatmentIDs
        if allowed.isEmpty {
            doseOverrides.removeAll()
            return
        }
        doseOverrides = doseOverrides.filter { allowed.contains($0.key) }
    }

    private func syncDerivedState() {
        recordTreatments = !selectedTreatmentIDs.isEmpty

        if let tepariID = tepariTreatmentID, !selectedTreatmentIDs.contains(tepariID) {
            tepariTreatmentID = nil
        }

        let shouldEnableTepari = tepariTreatmentID != nil
        if tepariGunEnabled != shouldEnableTepari {
            tepariGunEnabled = shouldEnableTepari
            onTepariChanged(shouldEnableTepari)
        }
    }

    private func removeTreatment(_ treatment: TreatmentTemplate) {
        let wasTepari = tepariTreatmentID == treatment.id

        selectedTreatmentIDs.remove(treatment.id)
        doseOverrides[treatment.id] = nil

        if wasTepari {
            tepariTreatmentID = nil
            tepariGunEnabled = false
            onTepariChanged(false)
        }

        syncDerivedState()
        onSelectionChanged()
    }

    // =========================================================
    // MARK: Dose adjustment helpers
    // =========================================================

    private func doseStep(for unit: DoseUnit) -> Double {
        switch unit.rawValue.lowercased() {
        case "ml", "mL".lowercased():
            return 0.1
        default:
            return 0.1
        }
    }

    private func adjustDose(for template: TreatmentTemplate, delta: Double) {
        var ov = existingOrSeededOverride(for: template)
        let current = Double(ov.value.replacingOccurrences(of: ",", with: ".")) ?? 0
        let updated = max(0, current + delta)
        ov.value = formattedNumberString(updated)
        doseOverrides[template.id] = ov
        onSelectionChanged()
    }

    private func adjustPerKg(for template: TreatmentTemplate, delta: Double) {
        var ov = existingOrSeededOverride(for: template)
        let current = Double((ov.perKg ?? template.dosePerKg ?? "10").replacingOccurrences(of: ",", with: ".")) ?? 10
        let updated = max(0, current + delta)
        ov.perKg = formattedNumberString(updated)
        doseOverrides[template.id] = ov
        onSelectionChanged()
    }

    private func formattedNumberString(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.000_001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private func sanitizedNumericString(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
    }

    // =========================================================
    // MARK: Display helpers
    // =========================================================

    private func overrideSummary(for template: TreatmentTemplate) -> String {
        let override = doseOverrides[template.id]
        let value = (override?.value ?? template.doseValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        let unit = (override?.unit ?? template.doseUnit).rawValue
        let basis = override?.basis ?? template.doseBasis
        let withholding = template.withholding.trimmingCharacters(in: .whitespacesAndNewlines)

        let doseText: String
        switch basis {
        case .perAnimal:
            doseText = "\(value) \(unit)"
        case .perBodyWeight:
            let perRaw = (override?.perKg ?? template.dosePerKg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let per = perRaw.isEmpty ? "10" : perRaw
            doseText = "\(value) \(unit) / \(per) kg"
        }

        if withholding.isEmpty { return doseText }
        return "\(doseText) • \(withholding)"
    }

    private func summaryLine(template: TreatmentTemplate) -> String {
        let value = template.doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withholding = template.withholding.trimmingCharacters(in: .whitespacesAndNewlines)

        let dosePart: String
        if value.isEmpty {
            dosePart = ""
        } else {
            switch template.doseBasis {
            case .perAnimal:
                dosePart = "\(value) \(template.doseUnit.rawValue)"
            case .perBodyWeight:
                let perRaw = (template.dosePerKg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let per = perRaw.isEmpty ? "10" : perRaw
                dosePart = "\(value) \(template.doseUnit.rawValue) / \(per) kg"
            }
        }

        if withholding.isEmpty { return dosePart }
        if dosePart.isEmpty { return withholding }
        return "\(dosePart) • \(withholding)"
    }

    private func resetNewTreatmentDraft() {
        newProduct = ""
        newDoseValue = ""
        newDoseUnit = .mL
        newDoseBasis = nil
        newDosePerKg = "10"
        newWithholding = ""
    }

    // =========================================================
    // MARK: Small reusable UI
    // =========================================================

    private func stepCard(title: String, subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Divider().opacity(0.18)

                content()
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func emptyStateCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(cardBackground)
        .overlay(cardStroke)
    }

    private func tagPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))

            Text(title)
                .font(.caption2.weight(.bold))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Capsule().fill(Color.blue.opacity(0.16)))
        .overlay(
            Capsule().stroke(Color.blue.opacity(0.28), lineWidth: 1)
        )
    }

    private func sheetSectionHeader(
        step: String,
        title: String,
        subtitle: String,
        isValid: Bool = false,
        required: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)

                    if required {
                        Text("Required")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isValid ? .green : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill((isValid ? Color.green : Color.orange).opacity(0.12))
                            )
                    } else if subtitle == "Optional" {
                        Text("Optional")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                }

                if subtitle != "Optional" {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if required || subtitle == "Optional" {
                Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isValid ? .green : .secondary)
                    .padding(.top, 1)
            }
        }
    }

    private func fieldCard<Content: View>(
        title: String,
        subtitle: String = "",
        required: Bool,
        isValid: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                if required {
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isValid ? .green : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill((isValid ? Color.green : Color.orange).opacity(0.12))
                        )
                }

                Spacer()

                if required {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isValid ? .green : .secondary)
                }
            }

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func infoCallout(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
    }

    private var cardBackground: some ShapeStyle {
        .ultraThinMaterial
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.10), lineWidth: 1)
    }
}
