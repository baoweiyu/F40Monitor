import Foundation

struct F40Message: Identifiable, Equatable, Sendable {
    let id: String
    let number: String
    let content: String
    let time: String
    let isUnread: Bool
}

struct F40Snapshot: Equatable, Sendable {
    var isReachable = false
    var isAuthenticated = false
    var firmware = "—"
    var simStatus = "未知"
    var modemState = "—"
    var networkType = "—"
    var operatorName = "—"
    var signalBars = 0
    var primarySignal = "—"
    var secondarySignal = "—"
    var sinr = "—"
    var rsrq = "—"
    var band = "—"
    var pci = "—"
    var downloadRate = "—"
    var uploadRate = "—"
    var monthlyTraffic = "—"
    var monthlyDownload = "—"
    var monthlyUpload = "—"
    var currentSessionTraffic = "—"
    var trafficMonth = "本月"
    var trafficLimit = "未设置"
    var trafficUsageRatio: Double?
    var connectedDeviceCount = 0
    var connectionStatus = "—"
    var unreadSMSCount = 0
    var messages: [F40Message] = []
    var lastUpdated: Date?
    var errorMessage: String?

    var isSIMDetected: Bool {
        simStatus != "未识别" && simStatus != "未知" && simStatus != "需要登录"
    }

    var hasCellularData: Bool {
        networkType != "—" || operatorName != "—" || primarySignal != "—"
    }

    static func parse(_ values: [String: String], at date: Date = Date()) -> F40Snapshot {
        var result = F40Snapshot()
        result.isReachable = true
        result.lastUpdated = date
        result.firmware = display(values["wa_inner_version"])
        result.modemState = display(values["mc_modem_main_state"])
        result.networkType = normalizedNetworkType(values["network_type"])
        result.operatorName = display(values["network_provider_fullname"])
        result.signalBars = Int(values["network_signalbar"] ?? "") ?? 0
        result.connectionStatus = display(values["ppp_status"])

        let monthlyRX = byteValue(values["flux_monthly_rx_bytes"])
        let monthlyTX = byteValue(values["flux_monthly_tx_bytes"])
        let sessionRX = byteValue(values["flux_realtime_rx_bytes"])
        let sessionTX = byteValue(values["flux_realtime_tx_bytes"])
        result.monthlyDownload = bytes(monthlyRX)
        result.monthlyUpload = bytes(monthlyTX)
        result.monthlyTraffic = bytes(monthlyRX + monthlyTX)
        result.currentSessionTraffic = bytes(sessionRX + sessionTX)
        if let month = values["date_month"], !month.isEmpty {
            result.trafficMonth = trafficPeriodLabel(fromResetDate: month)
        }

        if values["flux_data_volume_limit_switch"] == "1",
           values["flux_data_volume_limit_unit"] == "data",
           let limit = dataLimitBytes(values["flux_data_volume_limit_size"]), limit > 0 {
            result.trafficLimit = bytes(limit)
            result.trafficUsageRatio = min(Double(monthlyRX + monthlyTX) / Double(limit), 1)
        }

        let hasSIMIdentity = nonEmpty(values["sim_iccid"]) || nonEmpty(values["sim_imsi"])
        let rawSIMState = values["sim_pin_status"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if hasSIMIdentity {
            result.simStatus = rawSIMState.isEmpty ? "已识别" : rawSIMState
        } else {
            result.simStatus = rawSIMState.isEmpty ? "未识别" : rawSIMState
        }

        let is5G = result.networkType.localizedCaseInsensitiveContains("5G") ||
            result.networkType.localizedCaseInsensitiveContains("SA") ||
            result.networkType.localizedCaseInsensitiveContains("ENDC")
        if is5G {
            result.primarySignal = measurement(values["Z5g_rsrp"], unit: "dBm")
            result.secondarySignal = measurement(values["network_lte_rsrp"], unit: "dBm")
            result.sinr = measurement(firstNonEmpty(values["Z5g_SINR"], values["Z5g_snr"]), unit: "dB")
            result.rsrq = measurement(firstNonEmpty(values["Z5g_rsrq"], values["network_Z5g_rsrq"]), unit: "dB")
            result.band = display(firstNonEmpty(values["nr5g_action_band"], values["nr_band"]))
            result.pci = display(firstNonEmpty(values["nr5g_pci"], values["network_Z5g_PCI"]))
        } else {
            result.primarySignal = measurement(values["network_lte_rsrp"], unit: "dBm")
            result.secondarySignal = measurement(values["lte_rssi"], unit: "dBm")
            result.sinr = measurement(values["network_sinr"], unit: "dB")
            result.rsrq = measurement(firstNonEmpty(values["lte_rsrq"], values["network_Z_rsrq"]), unit: "dB")
            result.band = display(firstNonEmpty(values["wan_active_band"], values["network_lte_ca_pcell_band"]))
            result.pci = display(values["lte_pci"])
        }

        result.downloadRate = rate(values["flux_realtime_rx_thrpt"])
        result.uploadRate = rate(values["flux_realtime_tx_thrpt"])
        return result
    }

    private static func normalizedNetworkType(_ value: String?) -> String {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value == "NR5G-SA" || value == "SA" { return "5G RedCap" }
        if value == "ENDC" || value == "LTE-NSA" { return "5G NSA" }
        return value.isEmpty ? "—" : value
    }

    private static func measurement(_ value: String?, unit: String) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return "\(value) \(unit)"
    }

    private static func rate(_ value: String?) -> String {
        guard let value, let bytes = Double(value), bytes >= 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .decimal
        return formatter.string(fromByteCount: Int64(bytes)) + "/s"
    }

    private static func byteValue(_ value: String?) -> Int64 {
        guard let value, let number = Double(value), number >= 0 else { return 0 }
        return Int64(number)
    }

    private static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .decimal
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: value)
    }

    private static func dataLimitBytes(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let parts = value.split(separator: "_").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        let multiplier = parts.count > 1 ? parts[1] : 1
        return Int64(parts[0] * multiplier * 1_024 * 1_024)
    }

    private static func trafficPeriodLabel(fromResetDate value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count >= 8,
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)),
              let resetDate = Calendar(identifier: .gregorian).date(
                  from: DateComponents(year: year, month: month, day: day)
              ),
              let usageMonth = Calendar(identifier: .gregorian).date(byAdding: .month, value: -1, to: resetDate)
        else {
            return "本月"
        }

        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: usageMonth)
        guard let usageYear = components.year, let usageMonthNumber = components.month else { return "本月" }
        return String(format: "%04d%02d 月", usageYear, usageMonthNumber)
    }

    private static func display(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return value
    }

    private static func nonEmpty(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first { nonEmpty($0) } ?? nil
    }
}
