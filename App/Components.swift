import SwiftUI

extension View {
    func pointerCursor() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    @ViewBuilder
    func hideSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

struct InfoButton: View {
    let title: String
    let text: String
    @State private var showPopover = false
    
    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(text).font(.callout)
            }
            .padding()
            .frame(width: 250)
        }
    }
}

struct SidebarItem: View {
    let title: String
    let icon: String
    @Binding var selection: String?
    
    var body: some View {
        Button(action: { selection = title }) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(selection == title ? Color.accentColor : Color.clear)
            .foregroundColor(selection == title ? .white : .primary)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

struct OverrideWarning: View {
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .font(.callout)
            Spacer()
        }
        .padding(8)
        .background(Color.yellow.opacity(0.2))
        .foregroundColor(.orange)
        .cornerRadius(8)
        .padding(.top, 10)
        .padding(.horizontal)
    }
}

struct TickSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var tickInterval: Double
    var snapToInterval: Double
    
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.numberOfTickMarks = Int((range.upperBound - range.lowerBound) / tickInterval) + 1
        slider.allowsTickMarkValuesOnly = false
        slider.sliderType = .linear
        slider.controlSize = .regular
        return slider
    }
    
    func updateNSView(_ nsView: NSSlider, context: Context) {
        if nsView.doubleValue != value {
            nsView.doubleValue = value
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, snapTo: snapToInterval)
    }
    
    class Coordinator: NSObject {
        var value: Binding<Double>
        var snapTo: Double
        
        init(value: Binding<Double>, snapTo: Double) {
            self.value = value
            self.snapTo = snapTo
        }
        
        @objc func valueChanged(_ sender: NSSlider) {
            let snappedValue = (sender.doubleValue / snapTo).rounded() * snapTo
            if value.wrappedValue != snappedValue {
                value.wrappedValue = snappedValue
            }
        }
    }
}
