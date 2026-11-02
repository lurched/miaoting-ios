import SwiftUI

@main
struct MiaoTingApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            HomeView()
        }
        .sheet(isPresented: $state.showLogin) {
            LoginView().environmentObject(state)
        }
        .sheet(isPresented: $state.showPaywall) {
            PaywallView().environmentObject(state)
        }
        .overlay(alignment: .top) {
            if let toast = state.toast {
                ToastView(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { state.toast = nil }
                    }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.85), in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}
