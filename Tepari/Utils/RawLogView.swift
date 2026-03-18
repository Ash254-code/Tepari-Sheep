import SwiftUI
import UIKit

/// ✅ T1 / Transport raw log
/// This is currently the log produced by `TransportManager` (used for T1 TCP + Demo).
/// Racewell + Tru-Test will later have their own logs.
struct RawLogView: View {
    @EnvironmentObject private var transport: TransportManager

    @State private var showCopiedBanner = false

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 12) {

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {

                        StatusIndicatorView(title: "T1 Connection", state: transport.state)

                        HStack(spacing: 10) {
                            Button("Copy All") { copyAll() }
                                .buttonStyle(GlassButtonStyle())

                            Button("Clear") { transport.clearLog() }
                                .buttonStyle(GlassButtonStyle())
                        }

                        if showCopiedBanner {
                            Text("Copied to clipboard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }

                        Text("This log shows TCP traffic, state changes and parser/debug lines for the Te Pari T1 (and Demo mode).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                GlassCard {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {

                                if transport.log.isEmpty {
                                    Text("No log entries yet.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 10)
                                }

                                ForEach(transport.log) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        Text(entry.line)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .textSelection(.enabled)
                                    }
                                    .id(entry.id)

                                    Divider().opacity(0.2)
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: transport.log.count) { _, _ in
                            // Auto-scroll to latest
                            if let last = transport.log.last {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("T1 Raw Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func copyAll() {
        let formatter = ISO8601DateFormatter()
        let text = transport.log
            .map { entry in
                let t = formatter.string(from: entry.timestamp)
                return "\(t)  \(entry.line)"
            }
            .joined(separator: "\n")

        UIPasteboard.general.string = text

        withAnimation(.easeOut(duration: 0.15)) {
            showCopiedBanner = true
        }

        // Hide banner after a moment (no extra log spam)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.15)) {
                showCopiedBanner = false
            }
        }
    }
}
