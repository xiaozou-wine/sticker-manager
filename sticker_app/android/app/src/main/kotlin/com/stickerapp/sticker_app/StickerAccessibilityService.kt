package com.stickerapp.sticker_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.content.FileProvider
import java.io.File

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
    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        isRunning = true
        Log.i(TAG, "Accessibility service connected")
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
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
        val rootNode = rootInActiveWindow ?: return
        currentTargetPackage = QQ_PACKAGE

        // Confirmed selectors from GKD community subscriptions:
        // - ChatActivity: com.tencent.mobileqq.activity.ChatActivity
        // - Input field:  EditText[vid="input"]
        // - Chat content: [vid="chat_item_content_layout"]
        // - Send button:  [text="发送"] (needs snapshot verification)
        // - Emoji button: TODO: needs snapshot via gkd-kit/inspect

        val emojiPanel = findNodeByViewId(rootNode, "$QQ_PACKAGE:id/emoji_grid_layout")
            ?: findNodeByViewId(rootNode, "$QQ_PACKAGE:id/qqlist_emoji")
            ?: findNodeByText(rootNode, "表情")

        if (emojiPanel != null && !overlayShowing) {
            Log.d(TAG, "QQ emoji panel detected, showing overlay")
            showOverlay()
        } else if (emojiPanel == null && overlayShowing) {
            Log.d(TAG, "QQ emoji panel closed, hiding overlay")
            hideOverlay()
        }
    }

    private fun handleWeChatEvent(event: AccessibilityEvent) {
        currentTargetPackage = WECHAT_PACKAGE
        // Confirmed selectors:
        // - ChattingUI:     com.tencent.mm.ui.chatting.ChattingUI
        // - ChattingMainUI: com.tencent.mm.ui.chatting.variants.ChattingMainUI
        // - Input field:    EditText (no fixed id in WeChat)
        // - Send button:    [text="发送"]
        // - Emoji button:   [desc="表情"] (needs snapshot verification)
    }

    fun showOverlay(): Boolean {
        if (overlayShowing) return true
        overlayShowing = true
        if (overlayManager == null) {
            overlayManager = OverlayManager(this)
        }
        overlayManager?.show { stickerPath ->
            sendStickerToChat(stickerPath)
        }
        return true
    }

    fun hideOverlay(): Boolean {
        overlayShowing = false
        overlayManager?.hide()
        return true
    }

    private fun sendStickerToChat(stickerPath: String) {
        try {
            val file = File(stickerPath)
            if (!file.exists()) {
                Log.e(TAG, "Sticker file not found: $stickerPath")
                Toast.makeText(this, "表情文件不存在", Toast.LENGTH_SHORT).show()
                return
            }

            val imageUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )

            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clipData = ClipData.newUri(contentResolver, "sticker", imageUri)
            clipboard.setPrimaryClip(clipData)
            Log.d(TAG, "Image copied to clipboard: $imageUri")

            val rootNode = rootInActiveWindow ?: run {
                Log.w(TAG, "No active window found")
                Toast.makeText(this, "发送失败，请重试", Toast.LENGTH_SHORT).show()
                return
            }

            val inputField = findEditableNode(rootNode)
            if (inputField != null) {
                inputField.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                inputField.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                Log.d(TAG, "Pasted sticker into input field")

                handler.postDelayed({
                    // Send button: both QQ and WeChat use [text="发送"]
                    val sendButton = findNodeByText(rootInActiveWindow ?: return@postDelayed, "发送")
                    if (sendButton != null && sendButton.isEnabled) {
                        sendButton.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        Log.d(TAG, "Clicked send button")
                        handler.post { Toast.makeText(this, "表情已发送", Toast.LENGTH_SHORT).show() }
                    } else {
                        Log.w(TAG, "Send button not found or not enabled")
                        handler.post { Toast.makeText(this, "发送失败，请重试", Toast.LENGTH_SHORT).show() }
                    }
                    hideOverlay()
                }, 300)
            } else {
                Log.w(TAG, "No editable input field found")
                Toast.makeText(this, "发送失败，未找到输入框", Toast.LENGTH_SHORT).show()
                hideOverlay()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send sticker", e)
            Toast.makeText(this, "发送失败，请重试", Toast.LENGTH_SHORT).show()
            hideOverlay()
        }
    }

    private fun findNodeByText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val nodes = root.findAccessibilityNodeInfosByText(text)
        return nodes?.firstOrNull()
    }

    private fun findNodeByViewId(root: AccessibilityNodeInfo, viewId: String): AccessibilityNodeInfo? {
        val nodes = root.findAccessibilityNodeInfosByViewId(viewId)
        return nodes?.firstOrNull()
    }

    private fun findEditableNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findEditableNode(child)
            if (result != null) return result
        }
        return null
    }

    /**
     * Dump the current UI tree as a list of node info maps.
     * Each node contains: class, text, desc, vid, id, bounds, clickable, editable, depth.
     * Used for in-app UI inspection without ADB.
     */
    fun dumpNodeTree(): List<Map<String, Any?>> {
        val rootNode = rootInActiveWindow ?: return emptyList()
        val nodes = mutableListOf<Map<String, Any?>>()
        traverseNode(rootNode, 0, nodes)
        return nodes
    }

    private fun traverseNode(
        node: AccessibilityNodeInfo,
        depth: Int,
        result: MutableList<Map<String, Any?>>
    ) {
        val bounds = android.graphics.Rect()
        node.getBoundsInScreen(bounds)

        val info = mapOf(
            "depth" to depth,
            "class" to (node.className?.toString() ?: ""),
            "text" to (node.text?.toString() ?: ""),
            "desc" to (node.contentDescription?.toString() ?: ""),
            "vid" to (node.viewIdResourceName?.let {
                it.substringAfter("/", it)
            } ?: ""),
            "id" to (node.viewIdResourceName ?: ""),
            "bounds" to "[${bounds.left},${bounds.top},${bounds.right},${bounds.bottom}]",
            "clickable" to node.isClickable,
            "longClickable" to node.isLongClickable,
            "editable" to node.isEditable,
            "enabled" to node.isEnabled,
            "visible" to node.isVisibleToUser,
            "focusable" to node.isFocusable,
            "childCount" to node.childCount
        )
        result.add(info)

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            traverseNode(child, depth + 1, result)
        }
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
