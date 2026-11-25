import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import GardenCore

/// Photo check: the coach looks for water stress and nutrient problems and suggests organic
/// fixes in use-what-you-have order.
struct DiagnoseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Plant.created) private var plants: [Plant]
    @Query(sort: \Bed.created) private var beds: [Bed]

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var plantID: UUID?
    @State private var note = ""
    @State private var checking = false
    @State private var result: Diagnosis?
    @State private var resultIsDemo = false
    @State private var errorMessage: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result = result {
                        VStack(alignment: .leading, spacing: 16) {
                            DiagnosisResultView(diagnosis: result, isDemo: resultIsDemo)
                            resultActions(result)
                        }
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        Card { intro }
                        Card {
                            photoPicker
                            if image != nil { details }
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .gardenBackground()
            .navigationTitle("Photo check")
            .toolbar {
                if result != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New photo", action: reset)
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $image)
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item = item else { return }
                Task { await load(item) }
            }
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            CoachAvatar(size: 40)
            Text("Show me the plant. Get close enough to see the leaves clearly, in daylight, and include an older and a newer leaf if you can.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var photoPicker: some View {
        VStack(spacing: 12) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(image == nil ? "Choose photo" : "Choose another", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !plants.isEmpty {
                Picker("Which plant?", selection: $plantID) {
                    Text("Not one of mine / not sure").tag(UUID?.none)
                    ForEach(plants) { plant in
                        Text(plant.name).tag(UUID?.some(plant.id))
                    }
                }
                .pickerStyle(.menu)
            }
            TextField("Anything I should know? (optional)", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await check() }
            } label: {
                HStack {
                    if checking { ProgressView().tint(.white) }
                    Text(checking ? "Looking closely..." : "Check this plant")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(checking)
            Text("Photos are sent to the coach to be checked and aren't kept there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultActions(_ diagnosis: Diagnosis) -> some View {
        VStack(spacing: 10) {
            Button {
                saveToJournal(diagnosis)
            } label: {
                Label(saved ? "Saved to journal" : "Save to journal", systemImage: saved ? "checkmark" : "book.closed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(saved)
            Button {
                let plant = selectedPlant.map { " (\($0.name))" } ?? ""
                app.pendingCoachContext = CoachContext(kind: "photo", text: "Photo check\(plant): \(diagnosis.summary)")
                app.coachDraft = "About that photo check: what should I do first?"
                app.selectedTab = .coach
            } label: {
                Label("Ask \(app.coachName) about this", systemImage: "bubble.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var selectedPlant: Plant? {
        guard let id = plantID else { return nil }
        return plants.first { $0.id == id }
    }

    // MARK: Actions

    private func load(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
            image = picked
            errorMessage = nil
        } else {
            errorMessage = "Couldn't open that photo. Try another one."
        }
    }

    private func check() async {
        guard let image = image else { return }
        checking = true
        errorMessage = nil
        defer { checking = false }

        let plantName = selectedPlant?.name ?? ""
        if app.isDemo {
            try? await Task.sleep(nanoseconds: 800_000_000)
            result = DemoCoach.diagnosis(plantName: plantName)
            resultIsDemo = true
            return
        }
        guard let jpeg = ImagePrep.forCoach(image) else {
            errorMessage = "Couldn't prepare that photo. Try another one."
            return
        }
        let request = DiagnoseRequest(
            image: ImagePayload(mediaType: "image/jpeg", data: jpeg.base64EncodedString()),
            plantName: plantName,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            garden: app.snapshot()
        )
        do {
            result = try await app.coach.diagnose(request)
            resultIsDemo = false
        } catch {
            errorMessage = (error as? CoachAPIError)?.userMessage ?? "Something went wrong. Try again."
        }
    }

    private func saveToJournal(_ diagnosis: Diagnosis) {
        let line = diagnosis.journalNote.isEmpty ? "Photo check: \(diagnosis.overallValue.displayName.lowercased())" : diagnosis.journalNote
        let kind: JournalKind = diagnosis.overallValue == .pestOrDisease ? .pestOrDisease : .observation
        let entry = JournalEntry(day: app.today, kind: kind, what: line, source: "photo")
        if let plant = selectedPlant {
            entry.plantID = plant.id
            entry.plantName = plant.name
            if let bed = beds.first(where: { $0.id == plant.bedID }) {
                entry.bedID = bed.id
                entry.bedName = bed.name
            }
        }
        entry.notes = diagnosis.summary
        if let image = image { entry.setPhoto(ImagePrep.forJournal(image)) }
        entry.diagnosisData = try? JSONEncoder().encode(diagnosis)
        context.insert(entry)
        app.save()
        saved = true
    }

    private func reset() {
        result = nil
        image = nil
        pickerItem = nil
        note = ""
        saved = false
        errorMessage = nil
    }
}

/// Shows a diagnosis: what's likely going on, how sure, and fixes in tier order.
struct DiagnosisResultView: View {
    @Environment(AppModel.self) private var app
    let diagnosis: Diagnosis
    var isDemo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isDemo {
                Label("Demo result, not a real diagnosis.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: diagnosis.overallValue.symbol)
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(diagnosis.overallValue.displayName)
                        .font(.title2.bold())
                    Chip(text: diagnosis.confidenceValue.displayName, color: confidenceColor, symbol: "gauge.medium")
                }
            }
            Text(diagnosis.summary)
            if !diagnosis.photoQualityNote.isEmpty {
                Label(diagnosis.photoQualityNote, systemImage: "camera.metering.unknown")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if !diagnosis.findings.isEmpty {
                Text("What I see")
                    .font(.headline)
                ForEach(Array(diagnosis.findings.enumerated()), id: \.offset) { _, finding in
                    Card {
                        HStack {
                            Text(finding.issue)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Chip(text: finding.likelihoodValue.displayName, color: likelihoodColor(finding.likelihoodValue))
                        }
                        if !finding.evidence.isEmpty {
                            Text(finding.evidence)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !diagnosis.fixes.isEmpty {
                Text("What to do")
                    .font(.headline)
                ForEach(Array(diagnosis.fixes.enumerated()), id: \.offset) { _, fix in
                    FixCard(fix: fix)
                }
            }

            if diagnosis.soilTestSuggested {
                Card {
                    Label("A soil test would help", systemImage: "testtube.2")
                        .font(.subheadline.weight(.semibold))
                    if !diagnosis.soilTestReason.isEmpty {
                        Text(diagnosis.soilTestReason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("Your county's Cooperative Extension office runs basic soil tests for about $15 to $30.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !diagnosis.followUp.isEmpty {
                Label(diagnosis.followUp, systemImage: "calendar.badge.clock")
                    .font(.callout)
            }
        }
    }

    private var confidenceColor: Color {
        switch diagnosis.confidenceValue {
        case .high: return .green
        case .medium: return .orange
        case .low: return .secondary
        }
    }

    private func likelihoodColor(_ value: FindingLikelihood) -> Color {
        switch value {
        case .likely: return .red
        case .possible: return .orange
        case .unlikely: return .secondary
        }
    }
}

struct FixCard: View {
    let fix: Diagnosis.Fix

    var body: some View {
        Card {
            HStack(alignment: .top) {
                Text(fix.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Chip(text: fix.tierValue.displayName, color: fix.tierValue.color)
            }
            Text(fix.how)
                .font(.callout)
            if !fix.usesInventoryItem.isEmpty {
                Label("Uses your \(fix.usesInventoryItem)", systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !fix.product.isEmpty || !fix.price.isEmpty {
                Text([fix.product, fix.price].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
            }
            if !fix.pros.isEmpty {
                Label(fix.pros, systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if !fix.cons.isEmpty {
                Label(fix.cons, systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// The iPhone camera, for taking a plant photo.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    init(image: Binding<UIImage?>) {
        _image = image
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let picked = info[.originalImage] as? UIImage {
                parent.image = picked
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
