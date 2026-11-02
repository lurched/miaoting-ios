import SwiftUI
import UIKit

/// 「账号设置」：权益面板 + 关于 + 协议 + 退出。
///
/// 对应 Android `MainActivity.S()` 的 `i == 2` 分支。
struct AccountView: View {
    @EnvironmentObject private var state: AppState
    @State private var showTrace = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                entitlementCard
                aboutCard
                actionList
                if let trace = state.lastTrace, showTrace {
                    traceCard(trace)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ACCOUNT")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.2)
            Text("账号设置")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 4)
    }

    private var entitlementCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(state.user?.display ?? (state.isLoggedIn ? "已登录" : "未登录"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(state.entitlement?.stateLabel ?? "未开通")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.hasActiveEntitlement ? .black : Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(state.hasActiveEntitlement ? Theme.accent : Theme.surfaceHigh, in: Capsule())
            }

            Rectangle().fill(Theme.border).frame(height: 1)

            HStack(spacing: 0) {
                StatRow(label: "状态", value: state.entitlement?.stateLabel ?? "未开通",
                        valueColor: state.hasActiveEntitlement ? Theme.accent : Theme.textPrimary)
                StatRow(label: "套餐", value: planText)
            }

            HStack(spacing: 0) {
                StatRow(label: "到期时间", value: state.entitlement?.expiryLabel ?? "—")
                StatRow(label: "剩余", value: state.entitlement?.remainingLabel ?? "0小时")
                StatRow(label: "设备", value: state.entitlement?.deviceLabel ?? "0/5")
            }

            if !state.isLoggedIn {
                Button {
                    state.showLogin = true
                } label: {
                    Text("登录后进入快通道播放。")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Button {
                        state.showPaywall = true
                    } label: {
                        Text("套餐/权益")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await state.refreshEntitlement() }
                    } label: {
                        Text("刷新")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 76)
                            .padding(.vertical, 11)
                            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var planText: String {
        guard let label = state.entitlement?.planLabel, !label.isEmpty else { return "未开通" }
        return label
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("关于")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("秒听提供直播音频收听、我的直播间和账号权益服务。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text("版本 \(AppVersion.name)（\(AppVersion.code)）")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
            Text("APP备案：琼ICP备2026008627号-3A")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
            Text("ICP备案：琼ICP备2026008627号")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            row("用户协议") { state.openLegal(.terms) }
            divider
            row("隐私政策") { state.openLegal(.privacy) }
            divider
            row("联系客服") { state.showPaywall = true }
            divider
            row("检查更新") { Task { await state.checkUpdate() } }
            if state.isLoggedIn {
                divider
                row("退出账号", danger: true) { Task { await state.logout() } }
            }
            divider
            row(showTrace ? "收起调试信息" : "请求诊断") { showTrace.toggle() }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 14)
    }

    private func row(_ title: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(danger ? Theme.danger : Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func traceCard(_ trace: APIClient.Trace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(trace.method) \(trace.path)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .lineLimit(2)
            Text("HTTP \(trace.status)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(trace.status == 200 ? Theme.textSecondary : Theme.danger)
            Text(trace.body)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
