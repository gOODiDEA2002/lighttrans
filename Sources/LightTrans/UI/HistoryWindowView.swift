import SwiftUI
import AppKit

// 历史记录窗口（详细设计 13.3、v5 视觉基准）
struct HistoryWindowView: View {
    @State private var records: [HistoryRecord] = []
    @State private var pendingDevices = 0
    @State private var filter = ""
    @State private var selectedID: HistoryRecord.ID?
    private let isFixtureMode: Bool

    init() {
        isFixtureMode = false
    }

    #if DEBUG
    init(uiAcceptanceSnapshot: UIAcceptanceHistorySnapshot) {
        _records = State(initialValue: uiAcceptanceSnapshot.records)
        _pendingDevices = State(initialValue: uiAcceptanceSnapshot.pendingDevices)
        _filter = State(initialValue: uiAcceptanceSnapshot.filter)
        _selectedID = State(initialValue: uiAcceptanceSnapshot.selectedID)
        isFixtureMode = true
    }
    #endif

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
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchHeader
                if pendingDevices > 0 {
                    Text("另有 \(pendingDevices) 台设备的记录待从 iCloud 下载")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, V5.compactSpacing)
                }
                listView
            }
            .frame(width: V5.History.leftContentWidth)

            Rectangle()
                .fill(V5.dividerColor)
                .frame(width: V5.History.dividerWidth)

            detailView
                .frame(minWidth: V5.History.rightMinWidth, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !isFixtureMode else { return }
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyReload)) { _ in
            guard !isFixtureMode else { return }
            reload()
        }
    }

    // MARK: - 两行搜索头部（v5：76 pt）

    private var searchHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: V5.compactSpacing) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("搜索历史记录\u{2026}", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: V5.settingsBodyFontSize))
                    .onChange(of: filter) { _, _ in
                        syncSelectionAfterFilter()
                    }

                if !filter.isEmpty {
                    Button(action: {
                        filter = ""
                        syncSelectionAfterFilter()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("清空搜索")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                    .strokeBorder(V5.cardBorder, lineWidth: 1)
            )

            HStack {
                Text(filter.isEmpty
                     ? "共 \(records.count) 条记录"
                     : "找到 \(filtered.count) 条记录")
                    .font(.system(size: V5.captionFontSize))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("刷新")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .frame(height: V5.History.searchHeaderHeight)
    }

    // MARK: - 左侧列表（v5：64 pt 行高，白色 10% 选中背景 + 6 pt 圆角）
    // 使用 ScrollView + LazyVStack 精确控制行高和选中样式，
    // 替换原生 List/sidebar 的强蓝色选中态

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { record in
                    historyRow(for: record)
                        .frame(height: V5.History.listRowHeight)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(
                                cornerRadius: V5.History.selectedRowCornerRadius
                            )
                            .fill(selectedID == record.id
                                  ? Color.white.opacity(V5.History.selectedRowOpacity)
                                  : Color.clear)
                            .padding(.horizontal, 9)
                        )
                        .onTapGesture { selectedID = record.id }
                        .accessibilityAddTraits(
                            selectedID == record.id ? .isSelected : []
                        )
                }
            }
            .padding(.top, 8)
        }
    }

    private func historyRow(for record: HistoryRecord) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusDotColor(for: record))
                .frame(width: 6, height: 6)
                .accessibilityLabel(statusAccessibilityLabel(for: record))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.input)
                        .font(.system(size: V5.titleFontSize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(Self.shortTime(record.time))
                        .font(.system(size: V5.captionFontSize))
                        .foregroundColor(.secondary)
                        .fixedSize()
                }

                HStack {
                    Text(preferredTranslationSummary(for: record))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Spacer()
                    Text(record.device)
                        .font(.system(size: V5.captionFontSize))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 80)
                }
            }
        }
        .padding(.horizontal, 17)
    }

    private func preferredTranslationSummary(for record: HistoryRecord) -> String {
        let candidates = [record.literalOutput, record.output, record.rewriteOutput]
        for candidate in candidates {
            if let text = candidate, !text.isEmpty {
                return text.components(separatedBy: .newlines).first ?? text
            }
        }
        return "暂无译文"
    }

    // MARK: - 右侧详情区（v5：元数据 2 行 + 3 张正文卡片，带文字复制按钮）

    @ViewBuilder private var detailView: some View {
        if let record = selectedRecord {
            VStack(alignment: .leading, spacing: V5.sectionSpacing) {
                metadataCard(for: record)
                    .frame(height: 72)

                HistoryDetailCard(title: "原文", icon: "text.quote", content: record.input)
                    .frame(height: 104)

                if record.literalOutput != nil || record.rewriteOutput != nil {
                    HistoryDetailCard(
                        title: "直译",
                        icon: "character.book.closed",
                        content: displayText(record.literalOutput)
                    )
                    .frame(height: 104)
                    HistoryDetailCard(
                        title: "转写",
                        icon: "sparkles",
                        content: displayText(record.rewriteOutput)
                    )
                    .frame(height: 104)
                } else {
                    HistoryDetailCard(
                        title: "译文",
                        icon: "character.book.closed",
                        content: displayText(record.output)
                    )
                    .frame(height: 104)
                }
            }
            .padding(V5.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 10) {
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.4))
                Text(emptyStateMessage)
                    .font(.system(size: V5.settingsBodyFontSize))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyStateIcon: String {
        if records.isEmpty { return "tray" }
        if filtered.isEmpty { return "magnifyingglass" }
        return "doc.text.magnifyingglass"
    }

    private var emptyStateMessage: String {
        if records.isEmpty { return "暂无历史记录" }
        if filtered.isEmpty { return "无匹配记录" }
        return "选择左侧记录查看详情"
    }

    // MARK: - 元数据卡片（v5：2 行，时间+状态 / 设备+模型）

    private func metadataCard(for record: HistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: V5.compactSpacing) {
            HStack(alignment: .center) {
                Text(Self.fullTime(record.time))
                    .font(.system(size: V5.settingsBodyFontSize))
                    .foregroundColor(.secondary)
                Spacer()
                statusBadge(for: record)
            }

            HStack(alignment: .center, spacing: V5.sectionSpacing) {
                Text(record.device)
                    .font(.system(size: V5.settingsBodyFontSize))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(record.device)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(record.model)
                    .font(.system(size: V5.settingsBodyFontSize))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(record.model)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(V5.sectionSpacing)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .fill(V5.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .strokeBorder(V5.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder private func statusBadge(for record: HistoryRecord) -> some View {
        switch record.status {
        case "done":
            Text("完成")
                .font(.system(size: V5.captionFontSize))
                .foregroundColor(V5.successGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(V5.successGreen.opacity(0.12))
                .clipShape(Capsule())
        case "stopped":
            Text("已中途停止")
                .font(.system(size: V5.captionFontSize))
                .foregroundColor(V5.warningOrange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(V5.warningOrange.opacity(0.12))
                .clipShape(Capsule())
        case "failed":
            Text(record.error.map { "失败：\($0)" } ?? "失败")
                .font(.system(size: V5.captionFontSize))
                .foregroundColor(V5.errorRed)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(V5.errorRed.opacity(0.12))
                .clipShape(Capsule())
                .lineLimit(1)
        default:
            Text(record.status)
                .font(.system(size: V5.captionFontSize))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - 辅助方法

    private func statusDotColor(for record: HistoryRecord) -> Color {
        switch record.status {
        case "done": return V5.successGreen
        case "stopped": return V5.warningOrange
        case "failed": return V5.errorRed
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

// MARK: - 历史详情正文卡片（v5：标题栏 + 带文字复制按钮 + 分隔线 + 正文）

private struct HistoryDetailCard: View {
    let title: String
    let icon: String
    let content: String

    @State private var showCopied = false
    @State private var copyTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: V5.titleFontSize, weight: .semibold))
                Spacer()
                Button(action: performCopy) {
                    Text(showCopied ? "已复制" : "复制")
                        .font(.system(size: V5.captionFontSize))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(showCopied ? V5.successGreen : nil)
                .disabled(content.isEmpty || content == "（无输出）")
                .help(showCopied ? "已复制" : "复制\(title)")
                .accessibilityLabel("复制\(title)")
            }
            .padding(.horizontal, 10)
            .frame(height: V5.Panel.titleBarHeight)

            Divider()
                .padding(.horizontal, 8)

            ScrollView {
                Text(content)
                    .font(.system(size: V5.settingsBodyFontSize))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .scrollIndicators(.hidden)
        }
        .background(
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .fill(V5.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .strokeBorder(V5.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous))
    }

    private func performCopy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        showCopied = true
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            showCopied = false
        }
    }
}
