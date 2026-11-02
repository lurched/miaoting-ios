import SwiftUI

/// 根容器：三个 tab + 底部导航 + 全局弹层。
///
/// Android 端用 `MainActivity.i` 表示当前页（0 收听 / 1 我的直播间 / 2 账号设置），
/// 这里换成 `AppState.Tab`，页面内容拆到 ListenView / RoomsView / AccountView。
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch state.tab {
                case .listen: ListenView()
                case .rooms: RoomsView()
                case .account: AccountView()
                }
            }
            .padding(.bottom, 62)

            bottomBar
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

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(AppState.Tab.allCases) { tab in
                Button {
                    state.tab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(state.tab == tab ? Theme.accent : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            Theme.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.border).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
