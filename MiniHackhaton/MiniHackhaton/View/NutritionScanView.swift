//
//  NutritionScanView.swift
//  MiniHackhaton
//
//  Created by Training-28 on 14/07/26.
//

import PhotosUI
import SwiftUI
import UIKit

struct NutritionScanView: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var capturedImage: UIImage?
    @State private var isShowingCamera = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var nutritionItems: [NutritionItem] = []
    @State private var classification: HealthClassification?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Group {
                    if let capturedImage {
                        Image(uiImage: capturedImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ContentUnavailableView(
                            "No Photo Yet",
                            systemImage: "camera",
                            description: Text("Take a photo of a nutrition label to get started.")
                        )
                    }
                }
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if isProcessing {
                    ProgressView("Detecting nutrition facts…")
                        .padding(.top, 8)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    if let classification {
                        ClassificationBanner(classification: classification)
                            .padding(.horizontal)
                    }
                    if !nutritionItems.isEmpty {
                        List(nutritionItems) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.value)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listStyle(.plain)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.top)
            .navigationTitle("NutriDe")
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView(
                    onCapture: { image in
                        isShowingCamera = false
                        capturedImage = image
                        runDetection(on: image)
                    },
                    onCancel: {
                        isShowingCamera = false
                    }
                )
            }
            .onChange(of: photosPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    defer { photosPickerItem = nil }
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        await MainActor.run { errorMessage = "Could not load the selected photo." }
                        return
                    }
                    await MainActor.run {
                        capturedImage = image
                        runDetection(on: image)
                    }
                }
            }
        }
    }

    private func runDetection(on image: UIImage) {
        guard let detector = NutritionDetector.shared else {
            errorMessage = "Failed to load the detection model."
            return
        }

        nutritionItems = []
        classification = nil
        errorMessage = nil
        isProcessing = true
        announce("Foto diterima. Memindai label gizi, mohon tunggu.")

        Task.detached(priority: .userInitiated) {
            do {
                let result = try detector.scan(image)
                await MainActor.run {
                    isProcessing = false
                    nutritionItems = result.items
                    classification = result.classification
                    if result.items.isEmpty {
                        errorMessage = "No nutrition facts recognized. Try a clearer, well-lit photo."
                    } else {
                        announce(spokenSummary(for: result.classification))
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Detection failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Speaks the scan verdict aloud so a VoiceOver user hears the result immediately,
    /// without having to locate the banner by touch. No-op when VoiceOver is off.
    private func announce(_ message: String) {
        guard voiceOverEnabled else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func spokenSummary(for classification: HealthClassification) -> String {
        var summary = "Hasil pemindaian: \(classification.displayLabel), tingkat keyakinan \(Int(classification.confidence * 100)) persen."
        if !classification.missingFields.isEmpty {
            summary += " \(classification.missingFields.count) nilai gizi tidak terbaca dan diasumsikan buruk."
        }
        return summary
    }
}

extension HealthClassification {
    /// Human-readable form of the raw model label, shared by the banner and VoiceOver announcements.
    var displayLabel: String {
        switch label {
        case "sehat": return "Sehat"
        case "cukup sehat": return "Cukup Sehat"
        case "kurang sehat": return "Kurang Sehat"
        default: return label
        }
    }
}

private struct ClassificationBanner: View {
    let classification: HealthClassification

    private var tint: Color {
        switch classification.label {
        case "sehat": return .green
        case "cukup sehat": return .orange
        case "kurang sehat": return .red
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(classification.displayLabel)
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
                Text("\(Int(classification.confidence * 100))% yakin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !classification.missingFields.isEmpty {
                Text("\(classification.missingFields.count) nilai tidak terbaca, diasumsikan pesimis (mendekati profil kurang sehat).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NutritionScanView()
}
