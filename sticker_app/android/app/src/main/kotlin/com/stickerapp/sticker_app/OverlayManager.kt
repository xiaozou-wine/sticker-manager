package com.stickerapp.sticker_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import java.io.File

class OverlayManager(private val context: Context) {

    companion object {
        private const val TAG = "OverlayManager"
        private const val GRID_COLUMNS = 4
        private const val THUMBNAIL_SIZE_DP = 72
        private const val PADDING_DP = 8
    }

    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: View? = null
    private var isShowing = false
    private var onStickerSelected: ((String) -> Unit)? = null

    fun show(onSelected: (String) -> Unit) {
        if (isShowing) return
        onStickerSelected = onSelected

        val density = context.resources.displayMetrics.density
        val thumbSize = (THUMBNAIL_SIZE_DP * density).toInt()
        val padding = (PADDING_DP * density).toInt()

        // Build overlay layout
        val container = buildOverlayView(density, thumbSize, padding)
        overlayView = container

        val screenWidth = context.resources.displayMetrics.widthPixels
        val layoutParams = WindowManager.LayoutParams(
            (screenWidth * 0.8).toInt(),
            (density * 400).toInt(),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        }

        try {
            windowManager.addView(container, layoutParams)
            isShowing = true
            Log.d(TAG, "Overlay shown")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show overlay", e)
        }
    }

    fun hide() {
        if (!isShowing) return
        try {
            overlayView?.let { windowManager.removeView(it) }
            overlayView = null
            isShowing = false
            Log.d(TAG, "Overlay hidden")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to hide overlay", e)
        }
    }

    private fun buildOverlayView(density: Float, thumbSize: Int, padding: Int): View {
        // Root container with dark semi-transparent background
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#E6000000"))
            setPadding(padding, padding, padding, padding)
        }

        // Header bar with title and close button
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(padding, 0, padding, padding)
        }

        val title = TextView(context).apply {
            text = "选择表情"
            setTextColor(Color.WHITE)
            textSize = 16f
        }
        header.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        val closeBtn = TextView(context).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            textSize = 20f
            setPadding(padding * 2, padding, padding * 2, padding)
            setOnClickListener {
                StickerAccessibilityService.instance?.hideOverlay()
            }
        }
        header.addView(closeBtn)
        root.addView(header)

        // Sticker grid in a scrollable container
        val scrollView = ScrollView(context).apply {
            setBackgroundColor(Color.parseColor("#1AFFFFFF"))
        }

        // Load stickers grouped by pack
        val dataHelper = StickerDataHelper(context)
        val packs = dataHelper.getStickerPacks()
        Log.d(TAG, "Loaded ${packs.size} sticker packs")

        if (packs.isEmpty()) {
            val emptyText = TextView(context).apply {
                text = "暂无表情，请先在App中添加"
                setTextColor(Color.parseColor("#99FFFFFF"))
                textSize = 14f
                setPadding(padding * 2, padding * 4, padding * 2, padding * 4)
                gravity = Gravity.CENTER
            }
            val emptyLayout = FrameLayout(context)
            emptyLayout.addView(emptyText, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ).apply { gravity = Gravity.CENTER })
            scrollView.addView(emptyLayout)
        } else {
            val contentLayout = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
            }

            for (pack in packs) {
                val stickers = dataHelper.getStickersByPack(pack.id)
                if (stickers.isEmpty()) continue

                // Pack header
                val packLabel = TextView(context).apply {
                    text = "${pack.name}（${stickers.size}）"
                    setTextColor(Color.parseColor("#CCFFFFFF"))
                    textSize = 13f
                    setPadding(padding / 2, padding, padding / 2, padding / 2)
                }
                contentLayout.addView(packLabel)

                // Sticker grid for this pack
                val grid = GridLayout(context).apply {
                    columnCount = GRID_COLUMNS
                    useDefaultMargins = true
                }
                for (sticker in stickers) {
                    val itemView = createStickerItem(sticker.path, thumbSize, padding)
                    val params = GridLayout.LayoutParams().apply {
                        width = thumbSize + padding * 2
                        height = thumbSize + padding * 2
                        setMargins(padding / 2, padding / 2, padding / 2, padding / 2)
                    }
                    grid.addView(itemView, params)
                }
                contentLayout.addView(grid)
            }

            scrollView.addView(contentLayout)
        }

        root.addView(scrollView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        ))

        // Enable drag to reposition
        setupDrag(root)

        return root
    }

    private fun createStickerItem(path: String, thumbSize: Int, padding: Int): View {
        val frame = FrameLayout(context).apply {
            setPadding(padding / 2, padding / 2, padding / 2, padding / 2)
        }

        // Placeholder shown while thumbnail loads
        val placeholder = ProgressBar(context).apply {
            isIndeterminate = true
            indeterminateDrawable?.setTint(Color.parseColor("#44FFFFFF"))
        }
        frame.addView(placeholder, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.CENTER })

        val imageView = ImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            setBackgroundColor(Color.parseColor("#33FFFFFF"))
            alpha = 0f
            loadThumbnailAsync(this, placeholder, path, thumbSize)
        }

        frame.addView(imageView, FrameLayout.LayoutParams(thumbSize, thumbSize))
        frame.setOnClickListener {
            onStickerSelected?.invoke(path)
        }

        return frame
    }

    private fun loadThumbnailAsync(imageView: ImageView, placeholder: View, path: String, maxSize: Int) {
        Thread {
            try {
                val file = File(path)
                if (!file.exists()) return@Thread

                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeFile(path, options)

                val scale = maxOf(1, maxOf(options.outWidth, options.outHeight) / maxSize)
                val decodeOptions = BitmapFactory.Options().apply {
                    inSampleSize = scale
                }

                val bitmap = BitmapFactory.decodeFile(path, decodeOptions)
                imageView.post {
                    imageView.setImageBitmap(bitmap)
                    imageView.alpha = 1f
                    placeholder.visibility = View.GONE
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load thumbnail: $path", e)
                imageView.post { placeholder.visibility = View.GONE }
            }
        }.start()
    }

    private fun setupDrag(view: View) {
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false
        val dragThreshold = 10f * context.resources.displayMetrics.density

        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    val params = v.layoutParams as WindowManager.LayoutParams
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    false // Don't consume - let child clicks work
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (!isDragging && (dx * dx + dy * dy) > dragThreshold * dragThreshold) {
                        isDragging = true
                    }
                    if (isDragging) {
                        val params = v.layoutParams as WindowManager.LayoutParams
                        params.x = initialX + dx.toInt()
                        params.y = initialY + (-dy).toInt()
                        windowManager.updateViewLayout(v, params)
                    }
                    isDragging
                }
                else -> false
            }
        }
    }
}
