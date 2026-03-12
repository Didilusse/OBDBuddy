//
//  ContentView.swift
//  OBD2 Gauge
//
//  Created by Adil Rahmani on 3/7/26.
//

import SwiftUI

/// Selects the data source / transport for OBD-II communication.
enum ConnectionMode: String, CaseIterable {
    case csvPlayback = "CSV Playback"
    case ble = "BLE (Veepeak)"
    case tcp = "TCP (Emulator)"
}

struct ContentView: View {
    @State private var bleManager = BLEManager()
    @State private var tcpTransport = TCPTransport()
    @State private var driveStore = DriveStore()
    @State private var service = OBDService(mode: .csvPlayback)
    @State private var gaugeConfigStore = GaugeConfigStore()
    @State private var settingsStore = SettingsStore()
    @State private var connectionMode: ConnectionMode = .csvPlayback
    @State private var showingScanner = false

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(
                    service: service,
                    gaugeConfigStore: gaugeConfigStore,
                    settingsStore: settingsStore
                )
                .toolbar {
                    dashboardToolbar
                }
                .sheet(isPresented: $showingScanner) {
                    ScannerView(bleManager: bleManager)
                }
            }
            .tabItem {
                Label("Gauges", systemImage: "gauge.open.with.lines.needle.33percent.and" +
                      ".arrowtriangle")
            }

            NavigationStack {
                AllStatsView(readings: service.allReadings, settingsStore: settingsStore)
            }
            .tabItem {
                Label("All Stats", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                DriveHistoryView(driveStore: driveStore, settingsStore: settingsStore)
            }
            .tabItem {
                Label("Drives", systemImage: "car")
            }

            NavigationStack {
                SettingsView(settingsStore: settingsStore, gaugeConfigStore: gaugeConfigStore)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .onChange(of: connectionMode) {
            service.stop()
            switch connectionMode {
            case .csvPlayback:
                service = OBDService(mode: .csvPlayback)
            case .ble:
                service = OBDService(mode: .live)
                service.transport = bleManager
            case .tcp:
                service = OBDService(mode: .live)
                service.transport = tcpTransport
                if tcpTransport.transportState == .disconnected {
                    tcpTransport.connect()
                }
            }
            service.driveStore = driveStore
        }
        .onAppear {
            service.driveStore = driveStore
            service.start()
        }
    }

    private var isTransportReady: Bool {
        switch connectionMode {
        case .csvPlayback: return false
        case .ble: return bleManager.transportState == .ready
        case .tcp: return tcpTransport.transportState == .ready
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Connection", selection: $connectionMode) {
                    ForEach(ConnectionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if connectionMode == .ble {
                    Button {
                        showingScanner = true
                    } label: {
                        Label(
                            bleManager.transportState == .ready
                                ? "Connected: \(bleManager.connectedDeviceName ?? "Device")"
                                : "Connect Scanner",
                            systemImage: bleManager.transportState == .ready
                                ? "checkmark.circle.fill"
                                : "antenna.radiowaves.left.and.right"
                        )
                    }
                }

                if connectionMode == .tcp {
                    if tcpTransport.transportState == .ready {
                        Label("Connected: \(tcpTransport.connectedDeviceName ?? "Emulator")",
                              systemImage: "checkmark.circle.fill")
                    } else {
                        Button("Connect to Emulator") {
                            tcpTransport.connect()
                        }
                    }
                }
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                if connectionMode != .csvPlayback && isTransportReady {
                    Button {
                        if service.isRecording {
                            service.stopRecording()
                        } else {
                            service.startRecording()
                        }
                    } label: {
                        Image(systemName: service.isRecording ? "record.circle.fill" : "record.circle")
                            .foregroundStyle(service.isRecording ? .red : .primary)
                    }
                }

                Button {
                    if service.isRunning {
                        service.stop()
                    } else {
                        service.start()
                    }
                } label: {
                    Image(systemName: service.isRunning ? "stop.fill" : "play.fill")
                }
            }
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    let service: OBDService
    @Bindable var gaugeConfigStore: GaugeConfigStore
    var settingsStore: SettingsStore

    @State private var isEditing = false
    @State private var showingGaugePicker = false

    // Drag state
    @State private var draggedID: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var frameAtDragStart: CGRect = .zero

    private let cardHeight: CGFloat = 120
    private let spacing: CGFloat = 12

    var body: some View {
        ScrollView {
            if gaugeConfigStore.configs.isEmpty {
                ContentUnavailableView {
                    Label("No Gauges", systemImage: "gauge.open.with.lines.needle.33percent.and.arrowtriangle")
                } description: {
                    Text("Tap Edit then + to add gauges to your dashboard.")
                }
                .padding(.top, 80)
            } else {
                dashboardGrid
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("OBD-II Gauges")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if isEditing {
                        Button {
                            showingGaugePicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { isEditing.toggle() }
                    } label: {
                        Text(isEditing ? "Done" : "Edit")
                    }
                }
            }
        }
        .sheet(isPresented: $showingGaugePicker) {
            GaugePickerView(gaugeConfigStore: gaugeConfigStore)
        }
    }

    // MARK: - Dashboard Grid

    @ViewBuilder
    private var dashboardGrid: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let halfWidth = (totalWidth - spacing) / 2
            let frames = buildFrames(halfWidth: halfWidth, fullWidth: totalWidth)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(height: gridHeight(frames: frames))

                ForEach(Array(zip(gaugeConfigStore.configs, frames)), id: \.0.id) { config, frame in
                    let isDragged = draggedID == config.id
                    // The dragged card's visual position is always:
                    //   (where it was when drag started) + (finger translation)
                    // We subtract the current frame origin so it stays under the finger
                    // even after reordering changes the frame.
                    let visualOffset: CGSize = isDragged
                        ? CGSize(
                            width: frameAtDragStart.minX + dragTranslation.width - frame.minX,
                            height: frameAtDragStart.minY + dragTranslation.height - frame.minY
                        )
                        : .zero

                    gaugeCard(for: config)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX + visualOffset.width,
                                y: frame.minY + visualOffset.height)
                        .zIndex(isDragged ? 1 : 0)
                        .scaleEffect(isDragged ? 1.05 : 1.0)
                        .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 12, y: 8)
                        .gesture(dragGesture(for: config, currentFrame: frame, allFrames: frames))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: gaugeConfigStore.configs.map(\.id))
        }
        .frame(height: calculateGridHeight())
    }

    private func dragGesture(for config: GaugeConfig, currentFrame: CGRect, allFrames: [CGRect]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture())
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if draggedID == nil {
                        // Record the frame at the moment dragging starts
                        frameAtDragStart = currentFrame
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if !isEditing { isEditing = true }
                            draggedID = config.id
                        }
                    }
                    dragTranslation = drag?.translation ?? .zero

                    // The absolute position of the dragged card center
                    let dragCenter = CGPoint(
                        x: frameAtDragStart.midX + dragTranslation.width,
                        y: frameAtDragStart.midY + dragTranslation.height
                    )
                    reorderIfNeeded(dragCenter: dragCenter, allFrames: allFrames)
                default:
                    break
                }
            }
            .onEnded { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    draggedID = nil
                    dragTranslation = .zero
                }
            }
    }

    /// Reorder configs when the dragged card overlaps another card's frame.
    private func reorderIfNeeded(dragCenter: CGPoint, allFrames: [CGRect]) {
        guard let dragID = draggedID,
              let fromIndex = gaugeConfigStore.configs.firstIndex(where: { $0.id == dragID })
        else { return }

        for (i, frame) in allFrames.enumerated() where i != fromIndex {
            if frame.contains(dragCenter) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    gaugeConfigStore.configs.move(
                        fromOffsets: IndexSet(integer: fromIndex),
                        toOffset: i > fromIndex ? i + 1 : i
                    )
                }
                return
            }
        }
    }

    /// Build frame rects for each config.
    private func buildFrames(halfWidth: CGFloat, fullWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var row = 0
        var col = 0

        for config in gaugeConfigStore.configs {
            let span = config.isWide ? 2 : 1

            if col + span > 2 {
                row += 1
                col = 0
            }

            let x: CGFloat = col == 0 ? 0 : halfWidth + spacing
            let y = CGFloat(row) * (cardHeight + spacing)
            let w = span == 2 ? fullWidth : halfWidth

            frames.append(CGRect(x: x, y: y, width: w, height: cardHeight))

            col += span
            if col >= 2 {
                row += 1
                col = 0
            }
        }
        return frames
    }

    private func gridHeight(frames: [CGRect]) -> CGFloat {
        (frames.map { $0.maxY }.max() ?? 0)
    }

    /// Pre-calculate height for the GeometryReader so ScrollView sizes correctly.
    private func calculateGridHeight() -> CGFloat {
        var row = 0
        var col = 0
        for config in gaugeConfigStore.configs {
            let span = config.isWide ? 2 : 1
            if col + span > 2 {
                row += 1
                col = 0
            }
            col += span
            if col >= 2 {
                row += 1
                col = 0
            }
        }
        let totalRows = row + (col > 0 ? 1 : 0)
        return CGFloat(totalRows) * cardHeight + CGFloat(max(totalRows - 1, 0)) * spacing
    }

    // MARK: - Gauge Card

    @ViewBuilder
    private func gaugeCard(for config: GaugeConfig) -> some View {
        let rawValue = service.latestValueByPID[config.pidName]?.value
        let isTemp = PIDDescriptor.catalog[config.pidName]?.isTemperature ?? false
        let displayValue = isTemp ? settingsStore.convertTemperature(rawValue ?? 0) : (rawValue ?? 0)
        let displayUnit = isTemp ? settingsStore.temperatureUnitSymbol : config.unit
        let displayRange = isTemp ? settingsStore.convertTemperatureRange(config.range) : config.range
        let displayThreshold = isTemp ? settingsStore.convertTemperatureThreshold(config.warningThreshold) : config.warningThreshold

        ZStack(alignment: .topLeading) {
            GaugeCardView(
                title: config.displayTitle,
                value: displayValue,
                unit: displayUnit,
                range: displayRange,
                warningThreshold: displayThreshold,
                formatStyle: config.formatStyle
            )

            if isEditing {
                editOverlay(for: config)
            }
        }
        .compositingGroup()
        .modifier(JiggleModifier(isJiggling: isEditing && draggedID != config.id))
    }

    // MARK: - Edit Overlay

    @ViewBuilder
    private func editOverlay(for config: GaugeConfig) -> some View {
        HStack(spacing: 0) {
            Button {
                withAnimation {
                    if let idx = gaugeConfigStore.configs.firstIndex(where: { $0.id == config.id }) {
                        gaugeConfigStore.configs.remove(at: idx)
                    }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            }

            Spacer()

            Button {
                withAnimation {
                    gaugeConfigStore.toggleSize(for: config.id)
                }
            } label: {
                Image(systemName: config.isWide
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(8)
    }
}

// MARK: - Jiggle Modifier

struct JiggleModifier: ViewModifier {
    let isJiggling: Bool
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isJiggling ? angle : 0))
            .onChange(of: isJiggling, initial: true) {
                if isJiggling {
                    withAnimation(
                        .easeInOut(duration: 0.12)
                        .repeatForever(autoreverses: true)
                    ) {
                        angle = Double.random(in: 1.0...1.8) * (Bool.random() ? 1 : -1)
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        angle = 0
                    }
                }
            }
    }
}

#Preview {
    ContentView()
}
