import SwiftUI
import AppKit

// 历史窗口（详细设计 10.5）：左侧记录列表，右侧选中详情，顶部关键字过滤与刷新
struct HistoryWindowView: View {
    @State private var records: [HistoryRecord] = []
    @State private var pendingDevices = 0
    @State private var filter = ""
    @State private var selectedID: HistoryRecord.ID?

    // 关键字对原文与译文（含直译、转写、老记录单段）做包含匹配
    private var filtered: [HistoryRecord] {
        guard !filter.isEmpty else { return records }
        let key = filter.lowercased()
        return records.filter { record in
            let fields = [record.input, record.output, record.literalOutput, record.rewriteOutput]
            return fields.contains { $0?.lowercased().contains(key) == true }
        }
    }

    private var selectedRecord: HistoryRecord? {
        records.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if pendingDevices > 0 {
                Text("另有 \(pendingDevices) 台设备的记录待从 iCloud 下载")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            HSplitView {
                listView.frame(minWidth: 240, idealWidth: 272, maxWidth: 340)
                detailView.frame(minWidth: 340, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .historyReload)) { _ in reload() }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("按关键字过滤原文或译文", text: $filter)
                .textFieldStyle(.plain)
            Spacer()
            Button(action: reload) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var listView: some View {
        List(filtered, selection: $selectedID) { record in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Self.shortTime(record.time)).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(record.device).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Text(Self.summary(record.input)).font(.system(size: 13)).lineLimit(1)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private var detailView: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        metaLine("时间", Self.fullTime(record.time))
                        metaLine("设备", record.device)
                        metaLine("模型", record.model)
                        metaLine("状态", Self.statusText(record))
                    }
                    detailSection("原文", record.input)
                    // v1.1 双段记录分"直译""转写"展示；否则回退老记录单段译文
                    if record.literalOutput != nil || record.rewriteOutput != nil {
                        detailSection("直译", displayText(record.literalOutput))
                        detailSection("转写", displayText(record.rewriteOutput))
                    } else {
                        detailSection("译文", displayText(record.output))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("选择左侧一条记录查看详情")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
            Text(value).font(.caption).textSelection(.enabled)
        }
    }

    private func detailSection(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout).bold()
                Spacer()
                Button("复制") { copy(content) }.font(.caption)
            }
            Text(content)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        }
    }

    private func reload() {
        let result = HistoryStore.shared.loadAll()
        records = result.records
        pendingDevices = result.pendingDevices
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // 空或缺失的译文段显示占位文案
    private func displayText(_ value: String?) -> String {
        let text = value ?? ""
        return text.isEmpty ? "（无输出）" : text
    }

    // MARK: - 文本格式化

    private static func parse(_ s: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }

    private static func shortTime(_ s: String) -> String {
        guard let date = parse(s) else { return s }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func fullTime(_ s: String) -> String {
        guard let date = parse(s) else { return s }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func summary(_ input: String) -> String {
        let firstLine = input.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? input
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }

    private static func statusText(_ record: HistoryRecord) -> String {
        switch record.status {
        case "done": return "完成"
        case "stopped": return "已中途停止"
        case "failed": return "失败：\(record.error ?? "")"
        default: return record.status
        }
    }
}
