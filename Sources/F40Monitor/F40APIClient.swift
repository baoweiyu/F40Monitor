import CryptoKit
import Foundation

actor F40APIClient {
    static let defaultBaseURL = URL(string: "http://192.168.0.1")!

    private let baseURL: URL
    private let session: URLSession
    private var authenticated = false
    private var lastAuthenticationCheck = Date.distantPast
    private var cachedMessages: [F40Message] = []
    private var lastSMSFetch = Date.distantPast
    private var cachedConnectedDeviceCount = 0
    private var lastDeviceFetch = Date.distantPast

    private static let fields = [
        "wa_inner_version",
        "mc_modem_main_state",
        "sim_pin_status",
        "sim_iccid",
        "sim_imsi",
        "network_signalbar",
        "network_type",
        "network_provider_fullname",
        "network_lte_rsrp",
        "lte_rssi",
        "network_sinr",
        "network_Z_rsrq",
        "lte_rsrq",
        "lte_pci",
        "wan_active_band",
        "network_lte_ca_pcell_band",
        "Z5g_rsrp",
        "Z5g_SINR",
        "Z5g_snr",
        "Z5g_rsrq",
        "network_Z5g_rsrq",
        "network_Z5g_PCI",
        "nr5g_pci",
        "nr_band",
        "nr5g_action_band",
        "flux_realtime_rx_thrpt",
        "flux_realtime_tx_thrpt",
        "flux_realtime_rx_bytes",
        "flux_realtime_tx_bytes",
        "flux_monthly_rx_bytes",
        "flux_monthly_tx_bytes",
        "date_month",
        "flux_data_volume_limit_switch",
        "flux_data_volume_limit_size",
        "flux_data_volume_limit_unit",
        "flux_data_volume_alert_percent",
        "wifi_access_sta_num",
        "wifi_chip1_ssid1_access_sta_num",
        "wifi_chip2_ssid1_access_sta_num",
        "ppp_status",
        "sms_dev_unread_num",
        "sms_sim_unread_num"
    ]

    init(baseURL: URL = defaultBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 4
            configuration.timeoutIntervalForResource = 7
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpShouldSetCookies = true
            configuration.httpCookieAcceptPolicy = .always
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchSnapshot() async throws -> F40Snapshot {
        try await ensureAuthenticated()
        let values = try await getValues(Self.fields)
        var snapshot = F40Snapshot.parse(values)
        snapshot.isAuthenticated = true
        snapshot.unreadSMSCount = (Int(values["sms_dev_unread_num"] ?? "") ?? 0)
            + (Int(values["sms_sim_unread_num"] ?? "") ?? 0)

        if Date().timeIntervalSince(lastSMSFetch) >= 10 {
            cachedMessages = try await fetchMessages()
            lastSMSFetch = Date()
        }
        snapshot.messages = cachedMessages

        if Date().timeIntervalSince(lastDeviceFetch) >= 5 {
            do {
                cachedConnectedDeviceCount = try await fetchConnectedDeviceCount(fallbackValues: values)
            } catch {
                cachedConnectedDeviceCount = fallbackConnectedDeviceCount(values)
            }
            lastDeviceFetch = Date()
        }
        snapshot.connectedDeviceCount = cachedConnectedDeviceCount
        return snapshot
    }

    private func fetchConnectedDeviceCount(fallbackValues: [String: String]) async throws -> Int {
        let response = try await get([
            URLQueryItem(name: "cmd", value: "station_list"),
            URLQueryItem(name: "isTest", value: "false")
        ])
        if let stations = response["station_list"] as? [[String: Any]] {
            return stations.count
        }

        return fallbackConnectedDeviceCount(fallbackValues)
    }

    private func fallbackConnectedDeviceCount(_ values: [String: String]) -> Int {
        let direct = Int(values["wifi_access_sta_num"] ?? "")
        let first = Int(values["wifi_chip1_ssid1_access_sta_num"] ?? "") ?? 0
        let second = Int(values["wifi_chip2_ssid1_access_sta_num"] ?? "") ?? 0
        return direct ?? (first + second)
    }

    private func ensureAuthenticated() async throws {
        if authenticated, Date().timeIntervalSince(lastAuthenticationCheck) < 30 {
            return
        }

        let status = try await getValues(["loginfo"])
        if status["loginfo"] == "ok" {
            authenticated = true
            lastAuthenticationCheck = Date()
            return
        }

        try await login()
        authenticated = true
        lastAuthenticationCheck = Date()
    }

    private func login() async throws {
        let password = try KeychainCredential.password()
        let salt = try await getValues(["LD"])["LD"] ?? ""
        guard !salt.isEmpty else { throw F40Error.invalidResponse }

        let firstDigest = sha256(password)
        let loginDigest = sha256(firstDigest + salt)
        let response = try await post([
            "isTest": "false",
            "goformId": "LOGIN",
            "password": loginDigest
        ])
        guard response["result"] == "0" || response["result"] == "4" else {
            throw F40Error.loginFailed
        }
    }

    private func fetchMessages() async throws -> [F40Message] {
        let response = try await get([
            URLQueryItem(name: "cmd", value: "sms_data_total"),
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "data_per_page", value: "20"),
            URLQueryItem(name: "mem_store", value: "1"),
            URLQueryItem(name: "tags", value: "10"),
            URLQueryItem(name: "order_by", value: "order by id desc"),
            URLQueryItem(name: "isTest", value: "false")
        ])
        guard let rawMessages = response["messages"] as? [[String: Any]] else { return [] }

        return rawMessages.prefix(20).map { raw in
            let id = string(raw["id"])
            let number = string(raw["number"])
            let content = decodeMessage(string(raw["content"]))
            let tag = string(raw["tag"])
            return F40Message(
                id: id,
                number: number.isEmpty ? "未知号码" : number,
                content: content.isEmpty ? "（空短信）" : content,
                time: formatSMSDate(string(raw["date"])),
                isUnread: tag == "1"
            )
        }
    }

    private func getValues(_ fields: [String]) async throws -> [String: String] {
        let object = try await get([
            URLQueryItem(name: "cmd", value: fields.joined(separator: ",")),
            URLQueryItem(name: "multi_data", value: "1"),
            URLQueryItem(name: "isTest", value: "false")
        ])
        var values: [String: String] = [:]
        for (key, value) in object {
            let text = string(value)
            if !text.isEmpty || value is String { values[key] = text }
        }
        return values
    }

    private func get(_ queryItems: [URLQueryItem]) async throws -> [String: Any] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("goform/goform_get_cmd_process"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems + [
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1_000)))
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func post(_ form: [String: String]) async throws -> [String: String] {
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: baseURL.appendingPathComponent("goform/goform_set_cmd_process"))
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let object = try await perform(request)
        return object.reduce(into: [:]) { $0[$1.key] = string($1.value) }
    }

    private func perform(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(baseURL.appendingPathComponent("index.html").absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw F40Error.invalidResponse
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw F40Error.invalidJSON
        }
        return object
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02X", $0) }
            .joined()
    }

    private func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private func decodeMessage(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        var units: [UInt16] = []
        var index = value.startIndex
        while index < value.endIndex {
            let end = value.index(index, offsetBy: min(4, value.distance(from: index, to: value.endIndex)))
            if let unit = UInt16(value[index..<end], radix: 16), unit != 0, unit != 9 {
                units.append(unit)
            }
            index = end
        }
        return String(decoding: units, as: UTF16.self)
    }

    private func formatSMSDate(_ value: String) -> String {
        let parts = value.split(separator: ",").map(String.init)
        guard parts.count >= 5 else { return value }
        let year = parts[0].count == 2 ? "20\(parts[0])" : parts[0]
        return "\(year)-\(parts[1])-\(parts[2]) \(parts[3].leftPadded):\(parts[4].leftPadded)"
    }
}

enum F40Error: LocalizedError, Equatable {
    case invalidResponse
    case invalidJSON
    case noCredential
    case loginFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "F40 返回了无效的 HTTP 响应"
        case .invalidJSON: "F40 返回的数据格式无法识别"
        case .noCredential: "未在 macOS 钥匙串中找到 F40 管理密码"
        case .loginFailed: "F40 自动登录失败，请确认管理密码"
        }
    }
}

private extension String {
    var leftPadded: String { count >= 2 ? self : "0" + self }
}
