import SwiftUI
import PhotosUI

/// Builds a dish with the model: the user describes it or takes a photo,
/// reviews the estimated ingredients, then saves it as a reusable food.
struct AIDishView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onSave: (FoodItem) -> Void

    @State private var description = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showingCamera = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var estimate: AIDishEstimate?
    @State private var dishName = ""

    private var hasAPIKey: Bool { !(AppSecrets.claudeAPIKey ?? "").isEmpty }
    private var languageCode: String { Locale.current.language.languageCode?.identifier ?? "en" }

    var body: some View {
        NavigationStack {
            Form {
                if !hasAPIKey {
                    Section {
                        Label("ai.missingKey.hint", systemImage: "key.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Describe the dish") {
                    TextField("e.g. pasta with tomato sauce, 120 g, parmesan", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Or use a photo") {
                    HStack {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                        }
                        Spacer()
                        #if canImport(UIKit)
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                        }
                        #endif
                    }
                    if let imageData, let image = PlatformImage.make(from: imageData) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button(role: .destructive) {
                            self.imageData = nil
                            photoItem = nil
                        } label: {
                            Label("Remove photo", systemImage: "xmark.circle")
                        }
                    }
                }
                Section {
                    Button {
                        Task { await analyse() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().padding(.trailing, 6) }
                            Label(isLoading ? "Estimating…" : "Estimate nutrition", systemImage: "sparkles")
                        }
                    }
                    .disabled(isLoading || !hasAPIKey || (description.trimmingCharacters(in: .whitespaces).isEmpty && imageData == nil))
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
                if let estimate {
                    resultSections(estimate)
                }
            }
            .navigationTitle("AI dish")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(estimate == nil || dishName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        imageData = PlatformImage.jpeg(from: data) ?? data
                    }
                }
            }
            #if canImport(UIKit)
            .sheet(isPresented: $showingCamera) {
                CameraPicker { image in
                    imageData = ImageEncoding.jpegData(from: image)
                }
                .ignoresSafeArea()
            }
            #endif
        }
    }

    @ViewBuilder
    private func resultSections(_ estimate: AIDishEstimate) -> some View {
        Section("Result") {
            TextField("Dish name", text: $dishName)
            NutrientSummaryGrid(nutrients: estimate.totalNutrients)
            HStack {
                Text("Total weight")
                Spacer()
                Text("\(Format.grams(estimate.totalGrams)) g").foregroundStyle(.secondary)
            }
            HStack {
                Text("Confidence")
                Spacer()
                Text(Format.percent(estimate.confidence)).foregroundStyle(.secondary)
            }
            if !estimate.notes.isEmpty {
                Text(estimate.notes).font(.footnote).foregroundStyle(.secondary)
            }
        }
        Section("Ingredients") {
            ForEach(Array(estimate.ingredients.enumerated()), id: \.offset) { index, ingredient in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                        MacroSummaryText(nutrients: ingredient.nutrients)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Format.kcal(ingredient.calories)) kcal").monospacedDigit()
                        Text("\(Format.grams(ingredient.grams)) g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        removeIngredient(at: index)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func removeIngredient(at index: Int) {
        guard var current = estimate, current.ingredients.indices.contains(index) else { return }
        current.ingredients.remove(at: index)
        estimate = current
    }

    private func analyse() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AIDishEstimate
            if let imageData {
                result = try await AIFoodService.shared.estimate(imageJPEG: imageData, hint: description, language: languageCode)
            } else {
                result = try await AIFoodService.shared.estimate(description: description, language: languageCode)
            }
            estimate = result
            dishName = result.name
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard var current = estimate else { return }
        current.name = dishName.trimmingCharacters(in: .whitespaces)
        let food = current.makeFoodItem()
        store.insert(food)
        onSave(food)
        dismiss()
    }
}

/// Small bridge so image handling compiles on every platform.
enum PlatformImage {
    static func make(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }

    /// Re-encodes picked image data as a downsized JPEG.
    static func jpeg(from data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return ImageEncoding.jpegData(from: image)
        #else
        return nil
        #endif
    }
}
