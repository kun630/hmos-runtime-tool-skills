package ohos_app_cangjie_hm_metricx_cj.fps

import ohos.base.AppLog

public class FRTDispatcher {

    private static var instance: Option<FRTDispatcher> = None

    public static func GetInstance(): FRTDispatcher {
        if (instance.isNone()) {
            instance = FRTDispatcher()
        }
        instance.getOrThrow()
    }

    // ==================== 状态 ====================
    private var currentPage: String = ""
    private var active: Bool = false
    private var pageToken: Int64 = 0

    // 锁定本次nav的token（防延迟串帧）
    private var activeToken: Int64 = 0

    private var drawDone: Bool = false

    // ==================== click ====================
    public func onClick(): Unit {
        recordClickStart()
    }

    // ==================== nav ====================
    public func onNav(page: String): Unit {
        currentPage = page
        active = true
        drawDone = false

        pageToken += 1
        activeToken = pageToken   // 锁定当前链路

        recordNavigationTarget(page)
    }

    // ==================== draw ====================
    public func onDraw(): Unit {
        onDrawWithToken(activeToken)
    }

    // ==================== draw核心逻辑 ====================
    public func onDrawWithToken(token: Int64): Unit {
        if (!active) { return }
        if (drawDone) { return }

        // 只允许当前 activeToken
        if (token != activeToken) { return }

        drawDone = true
        active = false

        recordDrawEnd()
    }

    // ==================== reset ====================
    public func reset(): Unit {
        active = false
        drawDone = false
        currentPage = ""

        pageToken += 1
        activeToken = pageToken
    }

    // ==================== debug ====================
    public func dump(): Unit {
        AppLog.info("[FRTDispatcher] page=${currentPage}, active=${active}, token=${pageToken}, activeToken=${activeToken}, drawDone=${drawDone}")
    }
}