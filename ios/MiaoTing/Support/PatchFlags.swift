import Foundation

/// 与 patched APK 对齐的运行时开关。
///
/// 补丁事实（`tools/analyze_patch.py` 可复现）：
///
///   classes.dex @ 0x00ae60，方法 `Lcom/syncrozero/pro/MainActivity;->B()Z`
///   原始：`54 80 6e 00`  →  iget-object v0, v8, MainActivity->f:JSONObject
///   补丁：`12 10 0f 00`  →  const/4 v0, #1 ; return v0 ; nop
///
///   语义：权益门禁方法恒返回 true，方法体其余指令变成不可达代码。
///
/// 注意它只影响**客户端门禁**。服务端 `/api/live/discover` 是否二次校验权益，
/// 从客户端代码看不出来，属于 `unknown`，需要有效账号实测。
enum PatchFlags {

    /// `MainActivity.B()` → `return true`
    static let bypassEntitlementGate = true

    /// 与 Android 端一致：UI 上的权益状态仍按服务端返回的 `state` 字符串显示，
    /// 补丁只放开「能不能点播放/识别」这一层。
    static let mirrorsAndroidGateBehaviour = true
}
