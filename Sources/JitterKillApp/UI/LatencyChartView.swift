// LatencyChartView.swift — Pingwarden-style Swift Charts latency graph
// NOTE: @State is a SwiftUI macro unavailable in CLI builds.
// Chart timeframe state held in ObservableObject + @StateObject.

import SwiftUI
import Charts

// MARK: - Palette

enum LatencyPalette {
    static let excellent = Color.green
    static let good      = Color.teal
    static let fair      = Color.orange
    static let poor      = Color.red

    static func forLatency(_ ms: Double) -> Color {
        switch ms {
        case ..<20:  return excellent
        case ..<50:  return good
        case ..<100: return fair
        default:     return poor
        }
    }
}

// MARK: - Timeframe

struct TimeframeOption: Identifiable {
    let id = UUID()
    let label: String
    let minutes: Int
}

// MARK: - Chart State (ObservableObject — works in CLI builds)

final class LatencyChartState: ObservableObject {
    @Published var selectedTimeframe: Int = 5
}

// MARK: - Chart View

struct LatencyChartView: View {
    @EnvironmentObject var latencyEngine: LatencyEngine
    @StateObject private var chartState = LatencyChartState()

    private let timeframes: [TimeframeOption] = [
        TimeframeOption(label: "1m",  minutes: 1),
        TimeframeOption(label: "5m",  minutes: 5),
        TimeframeOption(label: "15m", minutes: 15),
        TimeframeOption(label: "30m", minutes: 30),
        TimeframeOption(label: "1h",  minutes: 60),
    ]

    private var filteredHistory: [PingResult] {
        let cutoff = Date().addingTimeInterval(-Double(chartState.selectedTimeframe) * 60)
        return latencyEngine.history.filter { $0.timestamp > cutoff }
    }

    private var successfulSegments: [[PingResult]] {
        var segments: [[PingResult]] = []
        var current: [PingResult] = []
        for probe in filteredHistory {
            if probe.success {
                current.append(probe)
            } else if !current.isEmpty {
                segments.append(current); current = []
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    private var failedProbes: [PingResult]   { filteredHistory.filter { !$0.success } }
    private var spikeProbes: [PingResult]    { filteredHistory.filter { $0.success && $0.latencyMs >= 100 } }
    private var latestSuccessful: PingResult? { filteredHistory.last(where: { $0.success }) }

    private var seriesColor: Color {
        guard let latest = latestSuccessful else { return LatencyPalette.excellent }
        return LatencyPalette.forLatency(latest.latencyMs)
    }

    private var chartYUpperBound: Double {
        let maxVal = filteredHistory.filter { $0.success }.map { $0.latencyMs }.max() ?? 100
        return (max(125, maxVal * 1.2) / 25).rounded(.up) * 25
    }

    private var windowStart: Date { Date().addingTimeInterval(-Double(chartState.selectedTimeframe) * 60) }
    private var windowEnd: Date   { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            chartBody
            legend
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) {
                Text("Ping History").font(.headline)
                Spacer()
                timeframePicker
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Ping History").font(.headline)
                timeframePicker
            }
        }
    }

    private var timeframePicker: some View {
        Picker("", selection: $chartState.selectedTimeframe) {
            ForEach(timeframes) { tf in Text(tf.label).tag(tf.minutes) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 260)
        .accessibilityLabel("Ping history timeframe")
    }

    // MARK: - Chart Body

    @ViewBuilder
    private var chartBody: some View {
        if filteredHistory.isEmpty {
            emptyStateView
        } else {
            chart
                .frame(height: 200)
                .chartXScale(domain: windowStart...windowEnd)
                .chartYScale(domain: 0...chartYUpperBound)
                .chartXAxis { xAxis }
                .chartYAxis { yAxis }
                .chartPlotStyle { p in p.padding(.trailing, 8) }
        }
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Good", 20))
                .foregroundStyle(LatencyPalette.good.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Fair", 50))
                .foregroundStyle(LatencyPalette.fair.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Poor", 100))
                .foregroundStyle(LatencyPalette.poor.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(successfulSegments.indices, id: \.self) { idx in
                ForEach(successfulSegments[idx]) { dp in
                    LineMark(
                        x: .value("Time", dp.timestamp),
                        y: .value("Ping", dp.latencyMs),
                        series: .value("Run", idx)
                    )
                    .foregroundStyle(seriesColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", dp.timestamp),
                        yStart: .value("Base", 0),
                        yEnd: .value("Ping", dp.latencyMs),
                        series: .value("Run", idx)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: seriesColor.opacity(0.25), location: 0),
                                .init(color: seriesColor.opacity(0.05), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            ForEach(spikeProbes) { dp in
                PointMark(x: .value("Time", dp.timestamp), y: .value("Ping", dp.latencyMs))
                    .foregroundStyle(LatencyPalette.forLatency(dp.latencyMs))
                    .symbolSize(22)
            }

            ForEach(failedProbes) { dp in
                RuleMark(x: .value("Lost", dp.timestamp))
                    .foregroundStyle(LatencyPalette.poor.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("Lost", dp.timestamp), y: .value("Lost", 0))
                    .foregroundStyle(LatencyPalette.poor)
                    .symbolSize(28)
            }

            if let latest = latestSuccessful {
                PointMark(x: .value("Now", latest.timestamp), y: .value("Ping", latest.latencyMs))
                    .foregroundStyle(seriesColor)
                    .symbolSize(50)
                    .annotation(position: .top, alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.0f ms", latest.latencyMs))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
            }
        }
    }

    // MARK: - Axes

    @AxisContentBuilder
    private var xAxis: some AxisContent {
        AxisMarks(values: xAxisTicks) { value in
            AxisGridLine(); AxisTick()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date, format: chartState.selectedTimeframe == 1
                        ? .dateTime.minute().second()
                        : .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                }
            }
        }
    }

    @AxisContentBuilder
    private var yAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
            AxisGridLine(); AxisTick()
            AxisValueLabel {
                if let v = value.as(Double.self) { Text("\(Int(v))ms").font(.caption2) }
            }
        }
    }

    private var xAxisTicks: [Date] {
        let count = chartState.selectedTimeframe <= 5 ? 4 : 5
        let duration = windowEnd.timeIntervalSince(windowStart)
        guard duration > 0 else { return [] }
        return (1...count).map { i in
            windowStart.addingTimeInterval(duration * Double(i) / Double(count + 1))
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text("Collecting ping data…").font(.caption).foregroundStyle(.secondary)
        }
        .frame(height: 200).frame(maxWidth: .infinity)
    }

    // MARK: - Legend

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 4) {
                legendItems
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var legendItems: some View {
        ChartLegendItem(color: LatencyPalette.excellent, label: "Excellent", detail: "<20ms")
        ChartLegendItem(color: LatencyPalette.good,      label: "Good",      detail: "20-50ms")
        ChartLegendItem(color: LatencyPalette.fair,      label: "Fair",      detail: "50-100ms")
        ChartLegendItem(color: LatencyPalette.poor,      label: "Poor",      detail: ">100ms")
        ChartLegendSymbol(systemImage: "xmark.circle.fill", color: LatencyPalette.poor, label: "Lost probe")
    }
}

private struct ChartLegendItem: View {
    let color: Color; let label: String; let detail: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) (\(detail))").foregroundStyle(.secondary)
        }
    }
}

private struct ChartLegendSymbol: View {
    let systemImage: String; let color: Color; let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
        }
    }
}
