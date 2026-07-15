//
//  HomeView.swift
//  MiniHackhaton
//
//  Created by Training-26 on 14/07/26.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: voiceOverEnabled ? "ear" : "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Text(voiceOverEnabled ? "Dibuka dengan VoiceOver" : "Dibuka tanpa VoiceOver")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onChange(of: voiceOverEnabled) { _, isOn in
            print("VoiceOver \(isOn ? "aktif" : "nonaktif")")
        }
    }
}

#Preview {
    HomeView()
}
