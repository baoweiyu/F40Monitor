import Testing
@testable import F40Monitor

@Suite("F40 snapshot parsing")
struct F40SnapshotTests {
    @Test("Empty SIM identifiers are reported as not recognized")
    func emptySIMAndFirmwareAreParsed() {
        let snapshot = F40Snapshot.parse([
            "wa_inner_version": "BD_CNMU3650V1.0.0B07",
            "sim_iccid": "",
            "sim_imsi": ""
        ])
        #expect(snapshot.isReachable)
        #expect(snapshot.firmware == "BD_CNMU3650V1.0.0B07")
        #expect(snapshot.simStatus == "未识别")
        #expect(!snapshot.isSIMDetected)
        #expect(!snapshot.hasCellularData)
    }

    @Test("5G fields take priority for a 5G SA connection")
    func signalSelection5G() {
        let snapshot = F40Snapshot.parse([
            "network_type": "NR5G-SA",
            "Z5g_rsrp": "-89",
            "network_lte_rsrp": "-102",
            "Z5g_SINR": "18",
            "nr5g_action_band": "n41",
            "nr5g_pci": "123",
            "sim_iccid": "present"
        ])
        #expect(snapshot.networkType == "5G SA")
        #expect(snapshot.primarySignal == "-89 dBm")
        #expect(snapshot.secondarySignal == "-102 dBm")
        #expect(snapshot.sinr == "18 dB")
        #expect(snapshot.band == "n41")
        #expect(snapshot.pci == "123")
        #expect(snapshot.simStatus == "已识别")
        #expect(snapshot.isSIMDetected)
        #expect(snapshot.hasCellularData)
    }

    @Test("Monthly traffic and configured data limit are parsed")
    func parsesTrafficSummary() {
        let snapshot = F40Snapshot.parse([
            "flux_monthly_rx_bytes": "1073741824",
            "flux_monthly_tx_bytes": "536870912",
            "date_month": "20260901",
            "flux_data_volume_limit_switch": "1",
            "flux_data_volume_limit_unit": "data",
            "flux_data_volume_limit_size": "2_1024"
        ])

        #expect(snapshot.monthlyTraffic != "—")
        #expect(snapshot.trafficMonth == "202608 月")
        #expect(snapshot.trafficLimit != "未设置")
        #expect(snapshot.trafficUsageRatio == 0.75)
    }
}
