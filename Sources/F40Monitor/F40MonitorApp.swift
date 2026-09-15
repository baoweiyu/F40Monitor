import AppKit
import SwiftUI

@main
struct F40MonitorApp: App {
    @StateObject private var model = MonitorModel()

    var body: some Scene {
        MenuBarExtra {
            MonitorPanel()
                .environmentObject(model)
                .onAppear { model.start() }
                .onDisappear { model.stop() }
        } label: {
            Label(menuTitle, systemImage: menuIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuTitle: String {
        guard model.snapshot.isReachable else { return "F40" }
        return model.snapshot.networkType == "—" ? "F40" : model.snapshot.networkType
    }

    private var menuIcon: String {
        model.snapshot.isReachable
            ? "antenna.radiowaves.left.and.right"
            : "antenna.radiowaves.left.and.right.slash"
    }
}

private struct MonitorPanel: View {
    @EnvironmentObject private var model: MonitorModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.13),
                    Color.purple.opacity(0.07),
                    Color.orange.opacity(0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                header

                if !model.snapshot.isReachable {
                    offlineCard
                } else if !model.snapshot.isAuthenticated {
                    loginErrorCard
                } else {
                    if model.snapshot.isSIMDetected {
                        trafficOverviewCard
                        smsCard
                        compactNetworkCard
                    } else {
                        simDiagnosticCard
                    }
                }

                footer
            }
            .padding(16)
        }
        .frame(width: 408)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.86))
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.cyan)
            }
            .frame(width: 44, height: 44)
            .shadow(color: .black.opacity(0.13), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("F40 Monitor")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("ZTE MU3650 · USB 蜂窝终端")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            StatusPill(isOnline: model.snapshot.isReachable)

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .rotationEffect(.degrees(model.isRefreshing ? 180 : 0))
            .animation(.easeInOut(duration: 0.35), value: model.isRefreshing)
        }
    }

    private var trafficOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.snapshot.trafficMonth)已用流量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.snapshot.monthlyTraffic)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("下载 \(model.snapshot.monthlyDownload)  ·  上传 \(model.snapshot.monthlyUpload)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.indigo)
                    Text("\(model.snapshot.connectedDeviceCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("台设备已连接")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let ratio = model.snapshot.trafficUsageRatio {
                VStack(spacing: 4) {
                    ProgressView(value: ratio)
                        .tint(ratio > 0.9 ? .red : .blue)
                    HStack {
                        Text("套餐用量")
                        Spacer()
                        Text("上限 \(model.snapshot.trafficLimit)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 10) {
                CompactRateMetric(
                    title: "实时下载",
                    value: model.snapshot.downloadRate,
                    icon: "arrow.down",
                    color: .green
                )
                CompactRateMetric(
                    title: "实时上传",
                    value: model.snapshot.uploadRate,
                    icon: "arrow.up",
                    color: .blue
                )
            }
        }
        .panelCard(tint: .indigo)
    }

    private var compactNetworkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("蜂窝网络")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        Text(networkTitle)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        if model.snapshot.operatorName != "—" {
                            Text(model.snapshot.operatorName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    SignalBars(level: model.snapshot.signalBars, active: model.snapshot.hasCellularData)
                    Text(signalQualityText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(signalQualityColor)
                }
            }

            HStack(spacing: 6) {
                NetworkDatum(title: "RSRP", value: model.snapshot.primarySignal)
                NetworkDatum(title: "SINR", value: model.snapshot.sinr)
                NetworkDatum(title: "频段", value: model.snapshot.band)
                NetworkDatum(title: "PCI", value: model.snapshot.pci)
            }
        }
        .panelCard(tint: .blue)
    }

    private var smsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("短信", systemImage: "message.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                if model.snapshot.unreadSMSCount > 0 {
                    Text("\(model.snapshot.unreadSMSCount) 条未读")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.red, in: Capsule())
                }
                Spacer()
                Button("查看全部") {
                    if let url = URL(string: "http://192.168.0.1/index.html#sms") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            if model.snapshot.messages.isEmpty {
                Text("暂无短信")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 3)
            } else {
                ForEach(Array(model.snapshot.messages.prefix(3).enumerated()), id: \.element.id) { index, message in
                    if index > 0 { Divider() }
                    HStack(spacing: 7) {
                        Circle()
                            .fill(message.isUnread ? Color.red : Color.purple.opacity(0.28))
                            .frame(width: 6, height: 6)
                        Text(message.number)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .frame(width: 82, alignment: .leading)
                        Text(message.content)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 2)
                        Text(message.time)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .panelCard(tint: .purple)
    }

    private var simDiagnosticCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.14))
                    Image(systemName: "simcard")
                        .foregroundStyle(.orange)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("未检测到 SIM 卡")
                        .font(.headline)
                    Text("蜂窝网络数据暂不可用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("F40 的 USB 与基带工作正常，但 IMSI、ICCID 和网络状态均为空。请检查 SIM 方向与卡槽接触，并在插卡后重新启动设备。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 8) {
                DeviceValue(title: "USB", value: "已连接", color: .green)
                DeviceValue(title: "管理地址", value: "192.168.0.1", color: .blue)
            }

            HStack {
                Text("固件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.snapshot.firmware)
                    .font(.caption.monospaced())
                    .lineLimit(1)
            }
        }
        .panelCard(tint: .orange)
    }

    private var offlineCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("等待 F40 连接")
                .font(.headline)
            Text("请确认 USB 网络服务已启用，并能访问 192.168.0.1。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .panelCard(tint: .orange)
    }

    private var loginErrorCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("F40 登录失败")
                .font(.headline)
            Text(model.snapshot.errorMessage ?? "请确认钥匙串中的 F40 管理密码。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .panelCard(tint: .orange)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                if let url = URL(string: "http://192.168.0.1/index.html#traffic_alert") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("流量设置", systemImage: "chart.pie.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 42, height: 36)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .bottomLeading) {
            Text(footerText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .offset(y: 14)
        }
        .padding(.bottom, 7)
    }

    private var networkTitle: String {
        if !model.snapshot.isSIMDetected { return "等待 SIM" }
        if model.snapshot.networkType == "—" { return "正在注册" }
        return model.snapshot.networkType
    }

    private var footerText: String {
        if let error = model.snapshot.errorMessage, !model.snapshot.isReachable { return error }
        guard let date = model.snapshot.lastUpdated else { return "尚未刷新" }
        return "更新于 \(date.formatted(date: .omitted, time: .standard))"
    }

    private func normalized(_ text: String, minimum: Double, maximum: Double) -> Double? {
        guard let first = text.split(separator: " ").first, let value = Double(first) else { return nil }
        return min(max((value - minimum) / (maximum - minimum), 0), 1)
    }

    private var signalQualityText: String {
        guard let quality = normalized(model.snapshot.primarySignal, minimum: -120, maximum: -70) else {
            return "等待信号"
        }
        if quality >= 0.72 { return "信号很好" }
        if quality >= 0.48 { return "信号良好" }
        if quality >= 0.28 { return "信号一般" }
        return "信号较弱"
    }

    private var signalQualityColor: Color {
        guard let quality = normalized(model.snapshot.primarySignal, minimum: -120, maximum: -70) else {
            return .secondary
        }
        if quality >= 0.48 { return .green }
        if quality >= 0.28 { return .orange }
        return .red
    }
}

private struct StatusPill: View {
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isOnline ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(isOnline ? "在线" : "离线")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

private struct SignalBars: View {
    let level: Int
    let active: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= level && active ? Color.green : Color.secondary.opacity(0.18))
                    .frame(width: 5, height: CGFloat(7 + index * 4))
            }
        }
        .frame(height: 28, alignment: .bottom)
    }
}

private struct CompactRateMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NetworkDatum: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct DeviceValue: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct PanelCardModifier: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.76),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder((tint ?? .white).opacity(tint == nil ? 0.18 : 0.10), lineWidth: 1)
            }
            .shadow(color: (tint ?? .black).opacity(0.06), radius: 10, y: 4)
    }
}

private extension View {
    func panelCard(tint: Color? = nil) -> some View {
        modifier(PanelCardModifier(tint: tint))
    }
}
