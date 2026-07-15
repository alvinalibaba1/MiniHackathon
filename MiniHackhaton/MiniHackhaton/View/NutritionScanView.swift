//
//  NutritionScanView.swift
//  MiniHackhaton
//
//  Created by Training-28 on 14/07/26.
//

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// Wraps one finished scan so the result sheet has everything it needs.
struct ScanDisplayResult: Identifiable {
    let id = UUID()
    let image: UIImage
    let scan: HealthScanResult
}

/// Google Lens-style scanner, presented fullscreen from the home dashboard: the live
/// camera fills the screen, with gallery and shutter in the bottom bar. Successful
/// scans are saved into `history` so the dashboard aggregates stay current.
struct NutritionScanView: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dismiss) private var dismiss
    @State private var cameraManager = CameraManager()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var scanResult: ScanDisplayResult?
    /// Set by the result sheet's "Done" button; once the sheet finishes
    /// dismissing, the camera closes too and the app lands back on home.
    @State private var finishAfterResult = false
    var history: ScanHistoryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraPreview

            // Aiming guide, purely decorative.
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 270, height: 320)
                Text("Point at the nutrition label")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                    .accessibilityLabel("Close camera")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                if isProcessing {
                    ProgressView("Scanning nutrition label…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 16)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }

                bottomBar
            }
        }
        .onAppear { cameraManager.startSession() }
        .onDisappear { cameraManager.stopSession() }
        .sheet(item: $scanResult, onDismiss: {
            // Dismissing the camera while the sheet is still animating away gets
            // swallowed by SwiftUI, so it waits here until the sheet is fully gone.
            if finishAfterResult {
                dismiss()
            }
        }) { result in
            ScanResultView(result: result) {
                finishAfterResult = true
                scanResult = nil
            }
        }
        .sensoryFeedback(.success, trigger: scanResult?.id)
        .onChange(of: photosPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                defer { photosPickerItem = nil }
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run { errorMessage = "The selected photo could not be loaded." }
                    return
                }
                await MainActor.run { runDetection(on: image) }
            }
        }
    }

    @ViewBuilder
    private var cameraPreview: some View {
        #if targetEnvironment(simulator)
        if let previewImage = cameraManager.previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            ProgressView("Waiting for Simulator camera…")
                .tint(.white)
                .foregroundStyle(.white)
        }
        #else
        CameraPreviewView(previewLayer: cameraManager.previewLayer)
            .ignoresSafeArea()
        #endif
    }

    private var bottomBar: some View {
        HStack {
            PhotosPicker(selection: $photosPickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
            }
            .accessibilityLabel("Choose photo from gallery")

            Spacer()

            if cameraManager.permissionDenied {
                Text("Camera access denied. Enable it in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            } else {
                Button {
                    if let image = cameraManager.capturePhoto() {
                        runDetection(on: image)
                    }
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.6), lineWidth: 4)
                                .frame(width: 86, height: 86)
                        )
                }
                .accessibilityLabel("Take photo")
                .accessibilityHint("Point the camera at the nutrition label, then double tap")
            }

            Spacer()

            // Invisible counterweight so the shutter stays centered.
            Color.clear
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private func runDetection(on image: UIImage) {
        guard let detector = NutritionDetector.shared else {
            errorMessage = "Failed to load the detection model."
            return
        }

        errorMessage = nil
        isProcessing = true
        announce("Photo received. Scanning the nutrition label, please wait.")

        Task.detached(priority: .userInitiated) {
            do {
                let scan = try detector.scan(image)
                await MainActor.run {
                    isProcessing = false
                    if scan.items.isEmpty {
                        errorMessage = "Couldn't read the nutrition label. Try again with better lighting."
                    } else {
                        history.add(ScanRecord(scan: scan))
                        scanResult = ScanDisplayResult(image: image, scan: scan)
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

    /// Speaks a status update when VoiceOver is on. No-op otherwise.
    private func announce(_ message: String) {
        guard voiceOverEnabled else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}

    final class PreviewContainerView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet { if let previewLayer { layer.addSublayer(previewLayer) } }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}

#Preview {
    NutritionScanView(history: ScanHistoryStore())
}
