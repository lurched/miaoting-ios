import SwiftUI
import UIKit

struct PaywallView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var serial = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var groupImage: UIImage?
    @State private var isLoadingGroup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if state.plans.isEmpty {
                        Card {
                            Text("套餐加载中，请稍后重试。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        ForEach(state.plans) { plan in
                            planRow(plan)
                        }
                    }

                    redeemCard
                    supportCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("开通权益")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .task {
            if state.plans.isEmpty { await state.refreshPlans() }
            await loadGroup()
        }
    }

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.hasActiveEntitlement ? "权益有效" : "尚未开通")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(state.hasActiveEntitlement ? Theme.accent : Theme.textPrimary)
                Text(state.entitlement?.summary ?? "购买后按套餐时长生效，设备绑定 2 台。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                if !state.isLoggedIn {
                    Button("先登录") { state.showLogin = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func planRow(_ plan: Plan) -> some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if plan.hasDiscount {
                            Text("限时")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.danger.opacity(0.18), in: Capsule())
                                .foregroundStyle(Theme.danger)
                        }
                    }
                    Text(plan.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.priceText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    if plan.hasDiscount {
                        Text(plan.originalPriceText)
                            .font(.system(size: 11))
                            .strikethrough()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Button("购买") {
                    Task { await state.purchase(plan) }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accent, in: Capsule())
            }
        }
    }

    private var redeemCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("授权码兑换")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 10) {
                    TextField("SYNCROZERO-XXXX-XXXX", text: $serial)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Theme.textPrimary)

                    Button(isRedeeming ? "兑换中" : "兑换") {
                        redeem()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .disabled(isRedeeming || serial.isEmpty)
                }
                if let redeemError {
                    Text(redeemError)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                }
            }
        }
    }

    private var supportCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("联系客服，加交流群")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if let groupImage {
                    Image(uiImage: groupImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                } else if isLoadingGroup {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                } else {
                    Text("客服二维码暂不可用。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func redeem() {
        redeemError = nil
        isRedeeming = true
        Task {
            do {
                try await state.redeem(serial)
                serial = ""
            } catch {
                redeemError = "授权码错误"
            }
            isRedeeming = false
        }
    }

    private func loadGroup() async {
        isLoadingGroup = true
        defer { isLoadingGroup = false }
        guard let group = try? await APIClient.shared.recoveryGroup(), let group else { return }
        groupImage = Self.decodeDataURL(group.qrDataURL)
    }

    static func decodeDataURL(_ text: String) -> UIImage? {
        guard text.isEmpty == false else { return nil }
        if text.hasPrefix("data:"), let comma = text.firstIndex(of: ",") {
            let base64 = String(text[text.index(after: comma)...])
            guard let data = Data(base64Encoded: base64) else { return nil }
            return UIImage(data: data)
        }
        if let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
            return nil
        }
        if let data = Data(base64Encoded: text) { return UIImage(data: data) }
        return nil
    }
}
