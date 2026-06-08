package com.stickerapp.sticker_app

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView

/**
 * A small persistent floating button that stays on screen.
 * When tapped, it triggers the sticker picker overlay.
 * Shows on top of QQ/WeChat so user can quickly pick a sticker.
 */
class TriggerButton(
    private val context: Context,
    private val onTap: () -> Unit
) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var buttonView: View? = null
    private var isShowing = false

    fun show() {
        if (isShowing) return

        val density = context.resources.displayMetrics.density
        val size = (48 * density).toInt()

        val button = ImageView(context).apply {
            setImageResource(android.R.drawable.ic_menu_gallery)
            setBackgroundColor(Color.parseColor("#CC2196F3"))
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(
                (8 * density).toInt(), (8 * density).toInt(),
                (8 * density).toInt(), (8 * density).toInt()
            )
        }

        val container = FrameLayout(context).apply {
            addView(button, FrameLayout.LayoutParams(size, size))
        }

        val layoutParams = WindowManager.LayoutParams(
            size, size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            x = 0
        }

        // Tap to open overlay, drag to move
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false
        val dragThreshold = 10 * density

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    val params = container.layoutParams as WindowManager.LayoutParams
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (!isDragging && (dx * dx + dy * dy) > dragThreshold * dragThreshold) {
                        isDragging = true
                    }
                    if (isDragging) {
                        val params = container.layoutParams as WindowManager.LayoutParams
                        params.x = initialX - dx.toInt()
                        params.y = initialY + dy.toInt()
                        windowManager.updateViewLayout(container, params)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        onTap()
                    }
                    true
                }
                else -> false
            }
        }

        try {
            windowManager.addView(container, layoutParams)
            buttonView = container
            isShowing = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun hide() {
        if (!isShowing) return
        try {
            buttonView?.let { windowManager.removeView(it) }
            buttonView = null
            isShowing = false
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
