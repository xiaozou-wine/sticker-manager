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
    private var triggerButton: TriggerButton? = null
    private var currentTargetPackage: String? = null
    private var overlayShowing = false
    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        isRunning = true
        Log.i(TAG, "Accessibility service connected")

        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            packageNames = arrayOf(QQ_PACKAGE, WECHAT_PACKAGE)
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 200
        }

        // Show persistent trigger button when service starts
        handler.post { showTriggerButton() }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return

        // Only track which app is in foreground, no auto-detection
        if (packageName == QQ_PACKAGE || packageName == WECHAT_PACKAGE) {
            currentTargetPackage = packageName
        }
    }

    fun showTriggerButton() {
        if (triggerButton == null) {
            triggerButton = TriggerButton(this) {
                showOverlay()
            }
        }
        triggerButton?.show()
    }

    fun hideTriggerButton() {
        triggerButton?.hide()
        triggerButton = null
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

            // Method 1: Try clipboard + paste
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clipData = ClipData.newUri(contentResolver, "sticker", imageUri)
            clipboard.setPrimaryClip(clipData)
            Log.d(TAG, "Image copied to clipboard: $imageUri")

            val rootNode = rootInActiveWindow
            if (rootNode != null) {
                val inputField = findEditableNode(rootNode)
                if (inputField != null) {
                    inputField.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                    handler.postDelayed({
                        inputField.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                        Log.d(TAG, "Pasted sticker into input field")

                        handler.postDelayed({
                            val sendButton = findNodeByText(rootInActiveWindow ?: return@postDelayed, "发送")
                            if (sendButton != null && sendButton.isEnabled) {
                                sendButton.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                                Log.d(TAG, "Clicked send button")
                                handler.post { Toast.makeText(this, "表情已发送", Toast.LENGTH_SHORT).show() }
                            } else {
                                Log.w(TAG, "Send button not found or not enabled - image copied to clipboard, paste manually")
                                handler.post { Toast.makeText(this, "已复制到剪贴板，请手动粘贴发送", Toast.LENGTH_LONG).show() }
                            }
                            hideOverlay()
                        }, 500)
                    }, 200)
                    return
                }
            }

            // Method 2: Fallback - use ACTION_SEND
            Log.d(TAG, "No input field found, falling back to ACTION_SEND")
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_STREAM, imageUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                setPackage(currentTargetPackage)
            }
            try {
                startActivity(shareIntent)
                handler.post { Toast.makeText(this, "选择聊天发送表情", Toast.LENGTH_SHORT).show() }
            } catch (e: Exception) {
                Log.e(TAG, "ACTION_SEND failed, copying to clipboard", e)
                handler.post { Toast.makeText(this, "已复制到剪贴板，请手动粘贴发送", Toast.LENGTH_LONG).show() }
            }
            hideOverlay()
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
