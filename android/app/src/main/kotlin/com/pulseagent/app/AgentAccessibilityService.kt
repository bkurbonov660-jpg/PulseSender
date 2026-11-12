package com.pulseagent.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class AgentAccessibilityService : AccessibilityService() {
    companion object {
        var instance: AgentAccessibilityService? = null
    }

    private val indexedNodes = mutableListOf<AccessibilityNodeInfo>()

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        if (instance == this) instance = null
        super.onDestroy()
    }

    fun getActivePackageName(): String {
        return rootInActiveWindow?.packageName?.toString() ?: ""
    }

    @Synchronized
    fun dumpUiTree(): String {
        indexedNodes.clear()
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        traverseNode(root, sb)
        return sb.toString().trim()
    }

    private fun traverseNode(node: AccessibilityNodeInfo?, sb: StringBuilder) {
        if (node == null || !node.isVisibleToUser) return

        val text = node.text?.toString()?.trim() ?: ""
        val desc = node.contentDescription?.toString()?.trim() ?: ""
        val hint = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            node.hintText?.toString()?.trim() ?: ""
        } else ""

        val label = when {
            text.isNotEmpty() -> text
            desc.isNotEmpty() -> desc
            hint.isNotEmpty() -> hint
            else -> ""
        }

        val isInteractive = node.isClickable || node.isEditable || node.isCheckable || node.isScrollable
        if (isInteractive || label.isNotEmpty()) {
            val idx = indexedNodes.size
            indexedNodes.add(node)
            val simpleClass = node.className?.toString()?.substringAfterLast('.') ?: "View"
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            val checkState = if (node.isCheckable) (if (node.isChecked) " [✓]" else " [ ]") else ""
            sb.append("[$idx] $simpleClass \"$label\"$checkState (${bounds.centerX()},${bounds.centerY()})\n")
        }

        for (i in 0 until node.childCount) {
            traverseNode(node.getChild(i), sb)
        }
    }

    @Synchronized
    fun tapNodeByIndex(index: Int, fallbackX: Float? = null, fallbackY: Float? = null): Boolean {
        if (index in indexedNodes.indices) {
            val node = indexedNodes[index]
            if (node.isClickable && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return true
            }
            var parent = node.parent
            while (parent != null) {
                if (parent.isClickable && parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                    return true
                }
                parent = parent.parent
            }
            val rect = Rect()
            node.getBoundsInScreen(rect)
            if (!rect.isEmpty) {
                return dispatchTap(rect.exactCenterX(), rect.exactCenterY(), 90L)
            }
        }
        if (fallbackX != null && fallbackY != null) {
            return dispatchTap(fallbackX, fallbackY, 90L)
        }
        return false
    }

    @Synchronized
    fun inputTextByIndex(index: Int, text: String): Boolean {
        val targetNode = if (index in indexedNodes.indices) {
            indexedNodes[index]
        } else {
            indexedNodes.firstOrNull { it.isEditable }
        } ?: return false

        targetNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        targetNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return targetNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    @Synchronized
    fun scrollScreen(direction: String): Boolean {
        val scrollable = indexedNodes.firstOrNull { it.isScrollable }
        if (scrollable != null) {
            val action = if (direction.equals("up", ignoreCase = true) ||
                direction.equals("backward", ignoreCase = true)
            ) {
                AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            } else {
                AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            }
            if (scrollable.performAction(action)) return true
        }
        val dm = resources.displayMetrics
        val cx = dm.widthPixels / 2f
        val topY = dm.heightPixels * 0.25f
        val botY = dm.heightPixels * 0.78f
        return when (direction.lowercase()) {
            "up" -> dispatchSwipe(cx, topY, cx, botY, 350L)
            "left" -> dispatchSwipe(dm.widthPixels * 0.85f, dm.heightPixels / 2f, dm.widthPixels * 0.15f, dm.heightPixels / 2f, 350L)
            "right" -> dispatchSwipe(dm.widthPixels * 0.15f, dm.heightPixels / 2f, dm.widthPixels * 0.85f, dm.heightPixels / 2f, 350L)
            else -> dispatchSwipe(cx, botY, cx, topY, 350L)
        }
    }

    fun performGlobalNavigation(actionName: String): Boolean {
        val globalAction = when (actionName.lowercase()) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            else -> GLOBAL_ACTION_BACK
        }
        return performGlobalAction(globalAction)
    }

    @Synchronized
    fun longPressByIndex(index: Int, durationMs: Long = 800L): Boolean {
        if (index !in indexedNodes.indices) return false
        val node = indexedNodes[index]
        if (node.isLongClickable && node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)) {
            return true
        }
        val rect = Rect()
        node.getBoundsInScreen(rect)
        return dispatchTap(rect.exactCenterX(), rect.exactCenterY(), durationMs.coerceIn(600L, 1200L))
    }

    fun dispatchTap(x: Float, y: Float, durationMs: Long = 80L): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    fun dispatchSwipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 350L): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    fun triggerScreenshot(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val ok = performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT)
            if (ok) "Скриншот сохранён в Галерею" else "Не удалось сделать скриншот"
        } else {
            "Скриншот требует Android 9+"
        }
    }
}
