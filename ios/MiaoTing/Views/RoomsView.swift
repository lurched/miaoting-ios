import SwiftUI

/// 「我的直播间」：搜索 + 添加 + 列表 + 排序。
///
/// 对应 Android `MainActivity.S()` 的 `i == 1` 分支。
struct RoomsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAddSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                searchRow
                listSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .sheet(isPresented: $showAddSheet) {
            AddRoomSheet().environmentObject(state)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            SectionHead("我的直播间", subtitle: "保存常用直播间，快速进入")
            Button {
                Task { await state.refreshRooms() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surfaceHigh, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                TextField("搜索直播间", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Button {
                showAddSheet = true
            } label: {
                Text("添加直播")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 96, height: 40)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var listSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("共 \(state.filteredRooms.count) 个")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Menu {
                    ForEach(AppState.SortMode.allCases) { mode in
                        Button(mode.rawValue) { state.sortMode = mode }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(state.sortMode.rawValue)
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 4)

            if state.filteredRooms.isEmpty {
                Text(state.searchText.isEmpty ? "我的直播间为空。" : "没有找到匹配的直播间。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(state.filteredRooms) { room in
                    roomRow(room)
                }
            }
        }
    }

    private func roomRow(_ room: Room) -> some View {
        HStack(spacing: 12) {
            Text(room.platformBadge.isEmpty ? "播" : room.platformBadge)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(Theme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(room.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(room.platformName)
                    Text("·")
                    Text("\(room.likeCount) 人收藏")
                    if room.ownedByCurrentUser {
                        Text("· 用户添加")
                            .foregroundStyle(Theme.accent.opacity(0.8))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                state.resolveAndPlay(room.roomUrl)
            } label: {
                Text("去听")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)

            if room.ownedByCurrentUser {
                Button {
                    Task { await state.deleteRoom(room) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// 添加直播间：名称 + 分享链接。
struct AddRoomSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var link = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 14) {
                    field("直播间名称", text: $name)
                    field("直播分享链接", text: $link)

                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().controlSize(.small).tint(.black) }
                            Text(busy ? "添加中" : "添加")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || name.isEmpty || link.isEmpty)

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("添加直播间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .font(.system(size: 14))
            .foregroundStyle(Theme.textPrimary)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submit() {
        error = nil
        busy = true
        Task {
            do {
                try await state.addRoom(name: name, url: link)
                state.toast = "直播间已添加。"
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
