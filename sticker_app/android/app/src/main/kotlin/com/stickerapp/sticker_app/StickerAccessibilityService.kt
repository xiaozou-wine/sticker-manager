package com.stickerapp.sticker_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class StickerAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "StickerA11y"
        private const val QQ_PACKAGE = "com.tencent.mobileqq"
        private const val WECHAT_PACKAGE = "com.tencent.mm"

        var instance: StickerAccessibilityService? = null
            private set

        var isRunning: Boolean = false
            private set
    }

    private var overlayManager: OverlayManager? = null
    private var currentTargetPackage: String? = null
    private var overlayShowing = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        isRunning = true
        Log.i(TAG, "Accessibility service connected")

        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                    AccessibilityEvent.TYPE_VIEW_CLICKED
            packageNames = arrayOf(QQ_PACKAGE, WECHAT_PACKAGE)
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 100
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return

        when (packageName) {
            QQ_PACKAGE -> handleQQEvent(event)
            WECHAT_PACKAGE -> handleWeChatEvent(event)
        }
    }

    private fun handleQQEvent(event: AccessibilityEvent) {
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                // Detect QQ chat window / emoji panel
                val rootNode = rootInActiveWindow ?: return
                currentTargetPackage = QQ_PACKAGE

                // TODO: Use gkd-kit/inspect to get real selectors
                // Placeholder: check if QQ's emoji button exists
                val emojiButton = findNodeByText(rootNode, "表情")
                if (emojiButton != null && !overlayShowing) {
                    Log.d(TAG, "QQ emoji button detected, showing overlay")
                    showOverlay()
                }
            }
        }
    }

    private fun handleWeChatEvent(event: AccessibilityEvent) {
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                currentTargetPackage = WECHAT_PACKAGE
                // TODO: Implement WeChat detection
            }
        }
    }

    fun showOverlay() {
        if (overlayShowing) return
        overlayShowing = true
        if (overlayManager == null) {
            overlayManager = OverlayManager(this)
        }
        overlayManager?.show { stickerPath ->
            sendStickerToChat(stickerPath)
        }
    }

    fun hideOverlay() {
        overlayShowing = false
        overlayManager?.hide()
    }

    /**
     * Send sticker image to current chat via clipboard + paste.
     * Flow: write image to clipboard -> find input field -> perform ACTION_PASTE -> click send.
     */
    private fun sendStickerToChat(stickerPath: String) {
        try {
            // 1. Copy image to clipboard
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val imageUri = Uri.parse(stickerPath)
            val clipData = ClipData.newUri(contentResolver, "sticker", imageUri)
            clipboard.setPrimaryClip(clipData)
            Log.d(TAG, "Image copied to clipboard: $stickerPath")

            // 2. Find input field in target app and paste
            val rootNode = rootInActiveWindow ?: run {
                Log.w(TAG, "No active window found")
                return
            }

            val inputField = findEditableNode(rootNode)
            if (inputField != null) {
                inputField.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                Log.d(TAG, "Pasted sticker into input field")

                // 3. Optional: click send button
                // TODO: selector needs real values from gkd-kit/inspect
                // val sendButton = findNodeByText(rootNode, "发送")
                // sendButton?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            } else {
                Log.w(TAG, "No editable input field found")
            }

            // 4. Hide overlay after sending
            hideOverlay()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send sticker", e)
        }
    }

    // --- Node search helpers ---

    private fun findNodeByText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val nodes = root.findAccessibilityNodeInfosByText(text)
        return nodes?.firstOrNull()
    }

    private fun findNodeByViewId(root: AccessibilityNodeInfo, viewId: String): AccessibilityNodeInfo? {
        val nodes = root.findAccessibilityNodeInfosByViewId(viewId)
        return nodes?.firstOrNull()
    }

    /**
     * Find the first editable node (input field) in the UI tree.
     */
    private fun findEditableNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findEditableNode(child)
            if (result != null) return result
        }
        return null
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        isRunning = false
        overlayManager?.hide()
        overlayManager = null
        Log.i(TAG, "Accessibility service destroyed")
    }
}
