package com.stickerapp.sticker_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class StickerAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "StickerA11y"
        const val QQ_PACKAGE = "com.tencent.mobileqq"
        const val WECHAT_PACKAGE = "com.tencent.mm"

        var instance: StickerAccessibilityService? = null
            private set
        var isRunning: Boolean = false
            private set
    }

    /** Package name of the current foreground target app, or null */
    var currentTargetPackage: String? = null
        private set

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        isRunning = true
        Log.i(TAG, "Accessibility service connected")

        KeepAliveService.start(this)

        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            packageNames = arrayOf(QQ_PACKAGE, WECHAT_PACKAGE)
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 200
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg = event.packageName?.toString() ?: return
        currentTargetPackage = if (pkg == QQ_PACKAGE || pkg == WECHAT_PACKAGE) pkg else null
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        isRunning = false
        Log.i(TAG, "Accessibility service destroyed")
    }

    // ==================== Overlay ====================

    fun showOverlay(): Boolean {
        // TODO: Phase 3 - implement overlay
        return false
    }

    fun hideOverlay(): Boolean {
        // TODO: Phase 3 - implement overlay
        return false
    }

    // ==================== Debug ====================

    fun dumpNodeTree(): List<Map<String, Any?>> {
        val rootNode = rootInActiveWindow ?: return emptyList()
        val nodes = mutableListOf<Map<String, Any?>>()
        traverseNode(rootNode, 0, nodes)
        return nodes
    }

    private fun traverseNode(
        node: android.view.accessibility.AccessibilityNodeInfo,
        depth: Int,
        result: MutableList<Map<String, Any?>>
    ) {
        val bounds = android.graphics.Rect()
        node.getBoundsInScreen(bounds)
        result.add(
            mapOf(
                "depth" to depth,
                "class" to (node.className?.toString() ?: ""),
                "text" to (node.text?.toString() ?: ""),
                "desc" to (node.contentDescription?.toString() ?: ""),
                "vid" to (node.viewIdResourceName?.let { it.substringAfter("/", it) } ?: ""),
                "id" to (node.viewIdResourceName ?: ""),
                "bounds" to "[${bounds.left},${bounds.top},${bounds.right},${bounds.bottom}]",
                "clickable" to node.isClickable,
                "editable" to node.isEditable,
                "enabled" to node.isEnabled,
                "visible" to node.isVisibleToUser,
                "childCount" to node.childCount
            )
        )
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            traverseNode(child, depth + 1, result)
        }
    }
}
