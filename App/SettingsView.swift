import SwiftUI
import Charts

struct SettingsView: View {
    let appDelegate: AppDelegate
    @ObservedObject var battery: BatteryState
    
    @State private var selection: String? = "General"
    
    @State private var chargeLimit: Double = 80
    @State private var lastChargeLimit: Double = 80
    @State private var startLimit: Double = 75
    @State private var isAudioWarningEnabled: Bool = false
    @State private var audioSoundName: String = "charging"
    @State private var showingChargeToFullAlert = false
    
    @State private var autoDischarge: Bool = false
    @State private var floatingMode: Bool = true
    @State private var heatProtection: Bool = true
    @State private var heatThreshold: Double = 35.0
    @State private var magSafeSync: Bool = true
    @State private var sleepDuringCharge: Bool = true
    @State private var sleepDuringDischarge: Bool = true
    @State private var powerUserMode: Bool = false
    
    private var hasChanges: Bool {
        return chargeLimit != Double(battery.maxLimit) ||
               startLimit != Double(battery.startLimit) ||
               isAudioWarningEnabled != battery.isAudioWarningEnabled ||
               audioSoundName != battery.audioSoundName ||
               autoDischarge != battery.autoDischarge ||
               floatingMode != battery.floatingMode ||
               heatProtection != battery.heatProtection ||
               heatThreshold != battery.heatThreshold ||
               magSafeSync != battery.magSafeSync ||
               sleepDuringCharge != battery.sleepDuringCharge ||
               sleepDuringDischarge != battery.sleepDuringDischarge ||
               powerUserMode != battery.powerUserMode
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // --- Custom Sidebar ---
            VStack(alignment: .leading, spacing: 5) {
                SidebarItem(title: "General", icon: "gearshape", selection: $selection)
                SidebarItem(title: "Advanced", icon: "slider.horizontal.3", selection: $selection)
                SidebarItem(title: "Protection", icon: "shield", selection: $selection)
                
                if powerUserMode {
                    Text("POWER USER")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 20)
                        .padding(.leading, 10)
                    
                    SidebarItem(title: "Analytics", icon: "chart.xyaxis.line", selection: $selection)
                    SidebarItem(title: "History", icon: "clock.arrow.circlepath", selection: $selection)
                }
                
                Spacer()
                
                // --- Sidebar Metadata ---
                VStack(alignment: .center, spacing: 8) {
                    Button(action: {
                        if let url = URL(string: "https://ko-fi.com/will2022") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("Buy me a coffee")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .pointerCursor()
                    
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    Text("Version \(version) (\(build))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
            }
            .frame(minWidth: 140)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.top, 20)
            .padding(.horizontal, 10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // --- Content Area ---
            VStack(spacing: 0) {
                if battery.heatProtectionTriggered {
                    OverrideWarning(text: "Heat Protection: Charging paused due to high battery temperature.")
                } else if battery.chargingToFull {
                    OverrideWarning(text: "Top Up Mode: Limits and overrides are bypassed to reach 100%.")
                } else if battery.adapterDisabled {
                    OverrideWarning(text: "Forced Battery Mode: The power adapter is virtually disconnected.")
                } else if battery.chargingDisabled {
                    OverrideWarning(text: "Charging Paused: Manual override is inhibiting the charge.")
                }

                Group {
                    switch selection {
                    case "General": generalTab
                    case "Advanced": advancedTab
                    case "Protection": protectionTab
                    case "Analytics": analyticsTab
                    case "History": historyTab
                    default: generalTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                footer
                    .padding()
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 650, height: 450)
        .onAppear {
            chargeLimit = Double(battery.maxLimit)
            lastChargeLimit = chargeLimit
            startLimit = Double(battery.startLimit)
            isAudioWarningEnabled = battery.isAudioWarningEnabled
            audioSoundName = battery.audioSoundName
            autoDischarge = battery.autoDischarge
            floatingMode = battery.floatingMode
            heatProtection = battery.heatProtection
            heatThreshold = battery.heatThreshold
            magSafeSync = battery.magSafeSync
            sleepDuringCharge = battery.sleepDuringCharge
            sleepDuringDischarge = battery.sleepDuringDischarge
            powerUserMode = battery.powerUserMode
        }
    }
    
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Charging Base Settings").font(.headline)
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Max Limit: \(Int(chargeLimit))%")
                            TickSlider(value: $chargeLimit, range: (powerUserMode ? 20...100 : 50...100), tickInterval: 5, snapToInterval: 5)
                                .frame(height: 20)
                                .onChange(of: chargeLimit) {
                                    let delta = chargeLimit - lastChargeLimit
                                    startLimit = min(chargeLimit, max((powerUserMode ? 15.0 : 20.0), startLimit + delta))
                                    lastChargeLimit = chargeLimit
                                }
                            InfoButton(title: "Max Charge Limit", text: "Sets the maximum percentage your battery will charge to. Keeping a battery between 20-80% significantly extends its long-term health.")
                        }
                        
                        HStack {
                            Text("Start Charging at: \(Int(startLimit))%")
                            TickSlider(value: $startLimit, range: 20...chargeLimit, tickInterval: 5, snapToInterval: 1)
                                .frame(height: 20)
                            InfoButton(title: "Lower Limit Re-engagement", text: "Defines a floor below which charging will not restart. This prevents 'micro-cycles' caused by frequently topping up. Your Mac will run on AC power but won't charge the battery until it drops below this limit.")
                        }
                        
                        if startLimit >= chargeLimit {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Start Limit should be lower than Max Limit for healthy floating")
                                    .font(.caption)
                            }
                            .foregroundColor(.orange)
                        }
                    }
                    
                    HStack {
                        Toggle("Pause Charging", isOn: Binding(
                            get: { battery.chargingDisabled },
                            set: { newValue in
                                battery.chargingDisabled = newValue
                                appDelegate.executeCommand(newValue ? .disableCharging : .chargeToLimit, battery: battery)
                            }
                        ))
                        Spacer()
                        InfoButton(title: "Pause Charging", text: "Manually stop the charging process. Your Mac will continue to run from the power adapter without charging the battery.")
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notifications").font(.subheadline).foregroundColor(.secondary)
                    VStack(alignment: .leading) {
                        HStack {
                            Toggle("Enable Audio Warning", isOn: $isAudioWarningEnabled)
                            Spacer()
                            Button("Test Sound") {
                                // Briefly swap the battery's sound to the UI selection for testing
                                let original = battery.audioSoundName
                                battery.audioSoundName = audioSoundName
                                battery.testSound()
                                battery.audioSoundName = original
                            }
                            .buttonStyle(.borderless)
                            .pointerCursor()
                            InfoButton(title: "Audio Warning", text: "Plays a notification sound whenever the system starts charging.")
                        }
                        
                        if isAudioWarningEnabled {
                            HStack {
                                Text("Sound:")
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 20)
                                Picker("", selection: $audioSoundName) {
                                    Text("Custom (Bundled)").tag("charging")
                                    Divider()
                                    Text("Ping").tag("Ping")
                                    Text("Hero").tag("Hero")
                                    Text("Basso").tag("Basso")
                                    Text("Funk").tag("Funk")
                                    Text("Pop").tag("Pop")
                                    Text("Tink").tag("Tink")
                                    Text("Glass").tag("Glass")
                                    Text("Submarine").tag("Submarine")
                                    Text("Purr").tag("Purr")
                                    Text("Blow").tag("Blow")
                                    Text("Sosumi").tag("Sosumi")
                                }
                                .frame(width: 150)
                                .onChange(of: audioSoundName) {
                                    let original = battery.audioSoundName
                                    battery.audioSoundName = audioSoundName
                                    battery.testSound()
                                    battery.audioSoundName = original
                                }
                            }
                        }
                    }

                    HStack {
                        Toggle("Sync MagSafe LED", isOn: $magSafeSync)
                        Spacer()
                        Button("Test LED") {
                            appDelegate.executeCommand(.testMagSafe, battery: battery)
                        }
                        .buttonStyle(.borderless)
                        .pointerCursor()
                        InfoButton(title: "MagSafe LED Sync", text: "Changes the MagSafe connector LED color based on the charging state: Orange while charging, Green when the limit is reached or charging is disabled, and Off during manual discharge.")
                    }
                }
            }
            .padding()
        }
    }
    
    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Discharge Controls").font(.headline)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Toggle("Force Battery Power", isOn: Binding(
                            get: { battery.adapterDisabled },
                            set: { newValue in
                                battery.adapterDisabled = newValue
                                appDelegate.executeCommand(newValue ? .disablePowerAdapter : .enablePowerAdapter, battery: battery)
                            }
                        ))
                        Spacer()
                        InfoButton(title: "Force Battery Power", text: "Virtually disconnect the power adapter to run entirely on battery. Useful for reducing charge level without physically unplugging.")
                    }
                    
                    HStack {
                        Toggle("Automatic Discharging", isOn: $autoDischarge)
                        Spacer()
                        InfoButton(title: "Automatic Discharging", text: "Automatically switch to battery power if your charge is above the set limit, then reconnect AC once the limit is reached.")
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Toggle("Enable Floating Mode", isOn: $floatingMode)
                        Spacer()
                        InfoButton(title: "Floating Mode", text: "Active Health Management: Instead of holding a static voltage, this lets the battery 'float' down to your start limit and then charge back up, keeping the chemistry active.")
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Developer & Power User").font(.subheadline).foregroundColor(.secondary)
                    HStack {
                        Toggle("Enable Power User Mode", isOn: $powerUserMode)
                        Spacer()
                        InfoButton(title: "Power User Mode", text: "Unlocks extended limit ranges (down to 20%) and other advanced controls. Recommended for experienced users only.")
                    }
                }
            }
            .padding()
        }
    }
    
    private var protectionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Environmental Protection").font(.headline)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Toggle("Heat Protection", isOn: $heatProtection)
                        Spacer()
                        if let temp = battery.batteryTemp {
                            Text(String(format: "%.1f°C", temp))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(temp > heatThreshold ? .red : .secondary)
                        }
                        InfoButton(title: "Heat Protection", text: "Automatically pauses charging if the battery temperature exceeds the set threshold.")
                    }
                    
                    if heatProtection {
                        VStack(alignment: .leading) {
                            Text("Temperature Threshold: \(Int(heatThreshold))°C").font(.subheadline)
                            Slider(value: $heatThreshold, in: 30...50, step: 1)
                        }
                        .padding(.leading, 20)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sleep & Clamshell Management").font(.subheadline).foregroundColor(.secondary)
                    
                    HStack {
                        Toggle("Stay Awake while Charging", isOn: $sleepDuringCharge)
                        Spacer()
                        InfoButton(title: "Wake while Charging", text: "Ensures the system stays awake to monitor and enforce your charge limits.")
                    }

                    HStack {
                        Toggle("Stay Awake while Discharging", isOn: $sleepDuringDischarge)
                        Spacer()
                        InfoButton(title: "Wake while Discharging", text: "Ensures the system stays awake when forcing battery power, especially critical for keeping the Mac active in Clamshell Mode.")
                    }
                }
            }
            .padding()
        }
    }
    
    private var analyticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Battery Analytics").font(.headline)
                    Spacer()
                    Button("Refresh Data") {
                        battery.update()
                    }
                    .buttonStyle(.borderless)
                    .pointerCursor()
                    .foregroundColor(.accentColor)
                }
                
                // --- Health & Capacity ---
                VStack(alignment: .leading, spacing: 10) {
                    Label("Health & Capacity", systemImage: "heart.fill")
                        .font(.subheadline).foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        statRow(label: "Battery Health:", value: String(format: "%.1f%%", battery.health), color: battery.health > 80 ? .green : .orange)
                        statRow(label: "Cycle Count:", value: "\(battery.cycleCount)")
                        Divider()
                        statRow(label: "Design Capacity:", value: "\(battery.designCapacity) mAh")
                        statRow(label: "Nominal Capacity:", value: "\(battery.nominalCapacity) mAh")
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // --- Real-time Power ---
                VStack(alignment: .leading, spacing: 10) {
                    Label("Real-time Power", systemImage: "bolt.fill")
                        .font(.subheadline).foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        statRow(label: "Total System Load:", value: String(format: "%.2f W", battery.systemPowerWatts))
                        statRow(label: "Battery Flow:", value: String(format: "%.2f W", battery.powerWatts), color: battery.powerWatts > 0 ? .green : (battery.powerWatts < 0 ? .orange : .primary))
                        statRow(label: "Current Voltage:", value: String(format: "%.2f V", battery.voltage))
                        statRow(label: "Current Amperage:", value: "\(battery.amperage) mA")
                        Divider()
                        statRow(label: "Current Capacity:", value: "\(battery.rawCurrentCapacity) mAh")
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // --- Thermal Sensors ---
                if !battery.temperatures.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Thermal Sensors", systemImage: "thermometer.medium")
                            .font(.subheadline).foregroundColor(.secondary)
                        
                        VStack(spacing: 8) {
                            ForEach(battery.temperatures.keys.sorted(), id: \.self) { key in
                                if let temp = battery.temperatures[key] {
                                    statRow(label: "\(key) Temp:", value: String(format: "%.1f°C", temp))
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                // --- Hardware & Adapter ---
                VStack(alignment: .leading, spacing: 10) {
                    Label("Hardware & Adapter", systemImage: "plug.fill")
                        .font(.subheadline).foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        statRow(label: "Adapter Power:", value: "\(battery.adapterWatts)W (\(battery.adapterDescription))")
                        Divider()
                        statRow(label: "Serial Number:", value: battery.batterySerial)
                        statRow(label: "Model Name:", value: battery.batteryModel)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    private var historyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text("Historical Data").font(.headline)
                
                if battery.history.isEmpty {
                    VStack {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No historical data available yet.")
                            .foregroundColor(.secondary)
                        Text("Data is collected every 60 seconds.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // --- Percentage Chart ---
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Battery Level (%)").font(.subheadline).foregroundColor(.secondary)
                            InfoButton(title: "Battery Level", text: "Shows your battery charge percentage over time. The blue line tracks how the level changes as ChargeControl enforces your configured limits.")
                        }
                        Chart(battery.history) { item in
                            LineMark(
                                x: .value("Time", item.date),
                                y: .value("Level", item.percentage)
                            )
                            .foregroundStyle(.blue)
                            AreaMark(
                                x: .value("Time", item.date),
                                y: .value("Level", item.percentage)
                            )
                            .foregroundStyle(.blue.opacity(0.1))
                        }
                        .frame(height: 150)
                        .chartYScale(domain: 0...100)
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisValueLabel("\(value.as(Int.self) ?? 0)%")
                            }
                        }
                    }
                    
                    Divider()
                    
                    // --- Power Flow Chart ---
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Power Flow (Watts)").font(.subheadline).foregroundColor(.secondary)
                            InfoButton(title: "Power Flow", text: "Shows the net power flowing into or out of the battery. Green (positive) means the battery is charging. Orange (negative) means the battery is discharging. Near-zero means the adapter is covering system load with no battery activity.")
                        }
                        
                        let powerValues = battery.history.map { $0.powerWatts }
                        let lineMax = powerValues.max() ?? 0.0
                        let lineMin = powerValues.min() ?? 0.0
                        let lineRange = lineMax - lineMin
                        let lineZeroOffset = lineRange == 0 ? 0.5 : lineMax / lineRange
                        let clampedLineZero = max(0.0, min(1.0, lineZeroOffset))
                        
                        let areaMax = max(lineMax, 0.0)
                        let areaMin = min(lineMin, 0.0)
                        let areaRange = areaMax - areaMin
                        let areaZeroOffset = areaRange == 0 ? 0.5 : areaMax / areaRange
                        let clampedAreaZero = max(0.0, min(1.0, areaZeroOffset))
                        
                        let chartMin = min(lineMin * 1.1, -10.0)
                        let chartMax = max(lineMax * 1.1, 10.0)
                        
                        let lineGradient = LinearGradient(
                            stops: [
                                .init(color: .green, location: 0.0),
                                .init(color: .green, location: clampedLineZero),
                                .init(color: .orange, location: clampedLineZero),
                                .init(color: .orange, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        let areaGradient = LinearGradient(
                            stops: [
                                .init(color: .green.opacity(0.3), location: 0.0),
                                .init(color: .green.opacity(0.3), location: clampedAreaZero),
                                .init(color: .orange.opacity(0.3), location: clampedAreaZero),
                                .init(color: .orange.opacity(0.3), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        Chart(battery.history) { item in
                            RuleMark(y: .value("Zero", 0))
                                .foregroundStyle(.secondary.opacity(0.5))
                            
                            AreaMark(
                                x: .value("Time", item.date),
                                y: .value("Power", item.powerWatts)
                            )
                            .foregroundStyle(areaGradient)
                            .interpolationMethod(.monotone)
                            
                            LineMark(
                                x: .value("Time", item.date),
                                y: .value("Power", item.powerWatts)
                            )
                            .foregroundStyle(lineGradient)
                            .interpolationMethod(.monotone)
                        }
                        .frame(height: 150)
                        .chartYScale(domain: chartMin...chartMax)
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisValueLabel(String(format: "%.1fW", value.as(Double.self) ?? 0.0))
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func statRow(label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    private var footer: some View {
        HStack {
            Button("Apply Settings") {
                appDelegate.applySettings(
                    chargeLimit: chargeLimit,
                    startLimit: startLimit,
                    floatingMode: floatingMode,
                    isAudioWarningEnabled: isAudioWarningEnabled,
                    audioSoundName: audioSoundName,
                    autoDischarge: autoDischarge,
                    heatProtection: heatProtection,
                    heatThreshold: heatThreshold,
                    magSafeSync: magSafeSync,
                    sleepDuringCharge: sleepDuringCharge,
                    sleepDuringDischarge: sleepDuringDischarge,
                    powerUserMode: powerUserMode,
                    battery: battery
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(hasChanges ? .accentColor : .secondary)
            .keyboardShortcut(.defaultAction)
            
            Spacer()
            
            if battery.chargingToFull {
                Button("Cancel Top Up") {
                    appDelegate.executeCommand(.chargeToLimit, battery: battery)
                }
                .foregroundColor(.red)
            } else {
                HStack {
                    Button("Charge to Full (Top Up)") {
                        showingChargeToFullAlert = true
                    }
                    InfoButton(title: "Top Up Mode", text: "Temporarily ignore all limits to reach 100%. Perfect for travel preparation.")
                }
                .alert("Top Up Battery?", isPresented: $showingChargeToFullAlert) {
                    Button("Start Top Up", role: .destructive) {
                        appDelegate.executeCommand(.chargeToFull, battery: battery)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will bypass your charge limits until the battery reaches 100% or Top Up is cancelled.")
                }
            }
        }
    }
}
