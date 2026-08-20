import SwiftUI
import AppKit

// 历史记录窗口（详细设计 13.3、UI 方案 v3.0）
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
        filtered.first { $0.id == selectedID }
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
                listView
                    .frame(minWidth: 240, idealWidth: 270, maxWidth: 340)
                detailView
                    .frame(minWidth: 340, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .historyReload)) { _ in reload() }
    }

    // MARK: - 顶部工具栏（含搜索框、匹配计数与刷新按钮）

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索历史记录…", text: $filter)
                .textFieldStyle(.plain)
                .onChange(of: filter) { _, _ in
                    syncSelectionAfterFilter()
                }

            Text(filter.isEmpty ? "共 \(records.count) 条" : "匹配 \(filtered.count) 条")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: reload) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 左侧列表区（微型语义色点 + 2 行摘要 + 低对比度设备次要文本）

    private var listView: some View {
        List(filtered, selection: $selectedID) { record in
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(statusDotColor(for: record))
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                    .accessibilityLabel(statusAccessibilityLabel(for: record))

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Self.shortTime(record.time))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(record.device)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }

                    Text(record.input)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 右侧详情区（元数据 2 行网格 + 3 张独立正文卡片）

    @ViewBuilder private var detailView: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 元数据 2 行网格卡片
                    metadataGrid(for: record)

                    // 原文卡片
                    DetailCard(title: "原文", icon: "text.quote", content: record.input)

                    // 直译与转写卡片（v1.1 双段展示；老记录单段降级展示）
                    if record.literalOutput != nil || record.rewriteOutput != nil {
                        DetailCard(
                            title: "直译",
                            icon: "character.book.closed",
                            content: displayText(record.literalOutput)
                        )
                        DetailCard(
                            title: "转写",
                            icon: "sparkles",
                            content: displayText(record.rewriteOutput)
                        )
                    } else {
                        DetailCard(
                            title: "译文",
                            icon: "character.book.closed",
                            content: displayText(record.output)
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // 空状态占位
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.4))
                Text(filtered.isEmpty ? "无匹配的历史记录" : "选择左侧一条记录查看详情")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 元数据 2 行网格

    private func metadataGrid(for record: HistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: 时间 + 状态 Badge
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(Self.fullTime(record.time))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusBadge(for: record)
            }

            // Row 2: 设备 + 模型名（均支持长文本尾部截断与 hover tooltip）
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(record.device)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(record.device)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(record.model)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(record.model)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder private func statusBadge(for record: HistoryRecord) -> some View {
        switch record.status {
        case "done":
            Text("完成")
                .font(.caption2)
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        case "stopped":
            Text("已中途停止")
                .font(.caption2)
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
        case "failed":
            Text(record.error.map { "失败：\($0)" } ?? "失败")
                .font(.caption2)
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .clipShape(Capsule())
                .lineLimit(1)
        default:
            Text(record.status)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - 辅助方法与状态处理

    private func statusDotColor(for record: HistoryRecord) -> Color {
        switch record.status {
        case "done": return .green
        case "stopped": return .orange
        case "failed": return .red
        default: return .secondary
        }
    }

    private func statusAccessibilityLabel(for record: HistoryRecord) -> String {
        switch record.status {
        case "done": return "翻译完成"
        case "stopped": return "已中途停止"
        case "failed": return "翻译失败：\(record.error ?? "")"
        default: return record.status
        }
    }

    private func syncSelectionAfterFilter() {
        let currentFiltered = filtered
        if currentFiltered.isEmpty {
            selectedID = nil
        } else if let id = selectedID, currentFiltered.contains(where: { $0.id == id }) {
            // 保持当前选中
        } else {
            selectedID = currentFiltered.first?.id
        }
    }

    private func reload() {
        let result = HistoryStore.shared.loadAll()
        records = result.records
        pendingDevices = result.pendingDevices
        syncSelectionAfterFilter()
    }

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
}

// MARK: - 独立正文卡片组件（带 1.5 秒绿色 checkmark 复制动效）

private struct DetailCard: View {
    let title: String
    let icon: String
    let content: String

    @State private var showCopied = false
    @State private var copyTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: performCopy) {
                    HStack(spacing: 3) {
                        if showCopied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                            Text("已复制")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                            Text("复制")
                                .font(.system(size: 11))
                        }
                    }
                    .frame(minWidth: 46)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(content.isEmpty || content == "（无输出）")
            }

            Text(content)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private func performCopy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        showCopied = true
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showCopied = false
        }
    }
}
