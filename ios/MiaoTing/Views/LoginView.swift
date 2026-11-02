import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phone = ""
    @State private var code = ""
    @State private var cooldown = 0
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var error: String?
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("手机号登录")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("登录后才会绑定设备权益，同一账号最多绑定 2 台设备。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)

                    TextField("手机号", text: $phone)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.textPrimary)

                    HStack(spacing: 10) {
                        TextField("6 位验证码", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Theme.textPrimary)

                        Button(cooldown > 0 ? "\(cooldown)s" : (isSending ? "发送中" : "获取验证码")) {
                            sendCode()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(cooldown > 0 ? Theme.textSecondary : Theme.accent)
                        .frame(width: 104, height: 48)
                        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 12))
                        .disabled(cooldown > 0 || isSending)
                    }

                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.danger)
                    }

                    Button {
                        verify()
                    } label: {
                        HStack(spacing: 6) {
                            if isVerifying { ProgressView().controlSize(.small).tint(.black) }
                            Text(isVerifying ? "登录中" : "登录")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(isVerifying || phone.count < 11 || code.count != 6)

                    Spacer()
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func sendCode() {
        guard phone.count == 11 else {
            error = "请输入 11 位手机号。"
            return
        }
        error = nil
        isSending = true
        Task {
            do {
                try await state.sendCode(phone)
                cooldown = 60
                startTimer()
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }

    private func verify() {
        error = nil
        isVerifying = true
        Task {
            do {
                try await state.verify(phone: phone, code: code)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isVerifying = false
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if cooldown > 0 { cooldown -= 1 } else { timer?.invalidate() }
        }
    }
}
