import SwiftUI

struct EnergyUsageView: View {
    @ObservedObject var battery: BatteryState
    @State private var viewMode: Int = 0 // 0: Live, 1: 24h History
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Energy Matrix", systemImage: "bolt.batteryblock.fill")
                        .font(.headline)
                    
                    Spacer()
                    
                    Picker("", selection: $viewMode) {
                        Text("Live").tag(0)
                        Text("24h History").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    
                    Button(action: {
                        battery.update()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(.borderless)
                    .pointerCursor()
                    .foregroundColor(.accentColor)
                }
                
                Text(viewMode == 0 ? 
                    "This dashboard shows real-time impact scores per application. High impact often indicates heavy CPU/GPU usage or disk activity." :
                    "Average energy impact over the last 24 hours. Helpful for identifying persistent background drain while the app was closed.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                let currentConsumers = viewMode == 0 ? battery.energyConsumers : battery.historicalEnergyConsumers
                
                if currentConsumers.isEmpty {
                    VStack(spacing: 20) {
                        if viewMode == 0 && battery.energyError != nil {
                            // ... error display ... (keeping logic for brevity in replacement)
                            if let error = battery.energyError {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                                Text("Analytics Unavailable").font(.headline)
                                Text(error).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                                Button("Try Again") { battery.update() }.buttonStyle(.bordered)
                            }
                        } else {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text(viewMode == 0 ? "Analyzing system energy distribution..." : "Fetching historical analytics...")
                                .foregroundColor(.secondary)
                                .font(.callout)
                            
                            Text(viewMode == 0 ? "This may take up to 30 seconds on the first run." : "Requires periodic background samples to populate.")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    VStack(spacing: 0) {
                        let topImpact = currentConsumers.first?.energyImpact ?? 1.0
                        
                        ForEach(currentConsumers) { consumer in
                            EnergyConsumerRow(consumer: consumer, maxImpact: topImpact, mode: viewMode)
                            
                            if consumer.id != currentConsumers.last?.id {
                                Divider().padding(.leading, 52)
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            if viewMode == 0 {
                                Text("Last updated: \(battery.lastEnergyUpdate.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Samples every 60s")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Retention: 7 days")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Avg. Impact per hour")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.05))
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                }
                
                // Optimization Tip
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("Optimization Tip")
                            .font(.subheadline)
                            .bold()
                    }
                    
                    Text("If you notice high background drain, check for apps with high idle Impact scores. Apps like browsers with many open tabs or heavy background syncers are often the culprits for preventing deep sleep.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.accentColor.opacity(0.05))
                .cornerRadius(10)
                .padding(.top, 10)
            }
            .padding()
        }
    }
}

struct EnergyConsumerRow: View {
    let consumer: ProcessEnergyInfo
    let maxImpact: Double
    let mode: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Group {
                if let icon = consumer.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.1))
                        Image(systemName: "cpu")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 28, height: 28)
            .padding(.leading, 12)
            
            // App Name & PID
            VStack(alignment: .leading, spacing: 2) {
                Text(consumer.name)
                    .font(.system(.body, design: .rounded))
                    .bold()
                    .lineLimit(1)
                
                if mode == 0 {
                    Text("PID \(consumer.id)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("Historical Average")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Impact score and bar
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", consumer.energyImpact))
                        .font(.system(.body, design: .monospaced))
                        .bold()
                    Text("Impact")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Visual progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.15))
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(impactColor(consumer.energyImpact))
                            .frame(width: geo.size.width * CGFloat(min(1.0, consumer.energyImpact / maxImpact)))
                    }
                }
                .frame(width: 80, height: 4)
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    
    private func impactColor(_ impact: Double) -> Color {
        if impact > 100 { return .red }
        if impact > 30 { return .orange }
        if impact > 5 { return .accentColor }
        return .secondary
    }
}
