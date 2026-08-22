import CoreGraphics

// 输入框高度计算纯函数：集中夹取与拖拽换算，便于单元测试复用
enum PanelInputHeightMath {
    static func clamped(_ value: CGFloat) -> CGFloat {
        min(V5.Panel.inputMax, max(V5.Panel.inputMin, value))
    }

    // 鼠标拖拽：向下拖（deltaY 为负）高度增大，向上拖（deltaY 为正）高度减小
    static func heightAfterDrag(baseHeight: CGFloat, deltaY: CGFloat) -> CGFloat {
        clamped(baseHeight - deltaY)
    }

    // 两张结果卡总预算：窗口内容区(600 - 上下内边距28)减去固定区(输入/手柄/操作栏/底栏)和 5 处垂直间距
    static func resultSectionHeight(inputHeight: CGFloat) -> CGFloat {
        let innerHeight = V5.Panel.height - V5.windowPadding * 2
        let fixedHeight = clamped(inputHeight) + V5.Panel.handleHeight + V5.Panel.actionRowHeight + V5.Panel.footerHeight
        let spacingTotal = V5.compactSpacing * 5
        let available = innerHeight - fixedHeight - spacingTotal
        return max(0, available / 2)
    }

    // 用于测试预算闭合：输入区 + 固定区 + 两张结果卡 + 间距 + 上下内边距
    static func composedPanelHeight(inputHeight: CGFloat) -> CGFloat {
        let section = resultSectionHeight(inputHeight: inputHeight)
        let fixedHeight = clamped(inputHeight) + V5.Panel.handleHeight + V5.Panel.actionRowHeight + V5.Panel.footerHeight
        let spacingTotal = V5.compactSpacing * 5
        return V5.windowPadding * 2 + fixedHeight + spacingTotal + section * 2
    }
}
