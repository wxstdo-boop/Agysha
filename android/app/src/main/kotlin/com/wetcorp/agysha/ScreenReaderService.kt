package com.wetcorp.agysha

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Читает текст активного окна, чтобы Ада (мини-окно) могла подсказать ответ
 * собеседнику и вообще видеть контекст экрана: и чужого приложения, и самого
 * Agysha (кроме окна Ады — его пропускаем, см. [isOverlayWindow]).
 *
 * Приватность: текст держится ТОЛЬКО в оперативной памяти этого процесса
 * (companion object), на диск не пишется и никуда не отправляется сам по
 * себе — Dart забирает его только в момент отправки сообщения в чат Ады.
 */
class ScreenReaderService : AccessibilityService() {

    companion object {
        @Volatile var latestText: String = ""
            private set
        @Volatile var latestPackage: String = ""
            private set
        @Volatile var latestAt: Long = 0L
            private set

        /** Живой экземпляр сервиса — нужен для снимка «прямо сейчас». */
        @Volatile private var instance: ScreenReaderService? = null

        /**
         * Снять экран НЕМЕДЛЕННО, не дожидаясь accessibility-события.
         *
         * Раньше снимок обновлялся только по событиям системы: человек
         * открывал чат Ады и спрашивал «что на экране», а Ада отдавала
         * старый снимок (или пустой) — «не видит экран». Теперь Dart просит
         * снимок в момент отправки сообщения, и мы обходим активное окно
         * прямо здесь.
         */
        fun captureNow(): Boolean {
            val svc = instance ?: return false
            return try {
                svc.captureFrom(svc.rootInActiveWindow, null)
            } catch (_: Exception) {
                false
            }
        }

        val isAlive: Boolean get() = instance != null
    }

    private var lastCaptureAt = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val pkg = event.packageName?.toString() ?: return

        // Клавиатуры не читаем: подсказки IME — шум вместо пользы.
        if (pkg.startsWith("com.android.inputmethod") || pkg.contains("inputmethod", ignoreCase = true)) return

        val now = System.currentTimeMillis()
        // Троттлинг: контент-события приходят на каждый чат-кадр мессенджера,
        // обход дерева на каждый из них зря грузит слабый телефон.
        if (now - lastCaptureAt < 600) return

        val root: AccessibilityNodeInfo? =
            if (event.source != null) event.source else rootInActiveWindow
        if (root == null) return

        // Свой пакет ЧИТАЕМ: владелец спрашивает Аду именно про экран
        // Agysha (привычки, задачи, питание), а прежний `pkg == packageName`
        // отбрасывал его целиком — «Ада видит экран» не работала нигде
        // внутри приложения. Пропускаем только окно самой Ады (оверлей
        // занимает малую часть экрана), иначе в снимок попадал её
        // собственный чат и она «отвечала сама себе».
        if (pkg == packageName && isOverlayWindow(root)) return

        lastCaptureAt = now
        captureFrom(root, pkg)
    }

    /**
     * Обходит активное окно и обновляет снимок. Возвращает true, если текст
     * собрался. [pkg] == null — берём пакет из корня (путь «по запросу»).
     */
    private fun captureFrom(root: AccessibilityNodeInfo?, pkgHint: String?): Boolean {
        root ?: return false
        val pkg = pkgHint ?: root.packageName?.toString() ?: packageName
        // Окно самой Ады не читаем: иначе она видит собственный чат.
        if (pkg == packageName && isOverlayWindow(root)) return false
        return try {
            val sb = StringBuilder()
            collect(root, sb, 0)
            val text = normalize(sb.toString())
            if (text.isEmpty()) {
                false
            } else {
                latestText = text
                latestPackage = pkg
                latestAt = System.currentTimeMillis()
                true
            }
        } catch (_: Exception) {
            false
        } finally {
            try { root.recycle() } catch (_: Exception) {}
        }
    }

    /**
     * Окно мини-Ады (оверлей) или пузырь: его корень заметно меньше экрана.
     * Главный экран Agysha занимает весь экран, поэтому порог 60% площади
     * разделяет их без дополнительных разрешений
     * (`getWindows()` требует flagRetrieveInteractiveWindows, а он
     * намеренно не объявлен — см. screen_reader_config.xml).
     */
    private fun isOverlayWindow(root: AccessibilityNodeInfo): Boolean {
        return try {
            val r = android.graphics.Rect()
            root.getBoundsInScreen(r)
            val dm = resources.displayMetrics
            val screen = dm.widthPixels.toLong() * dm.heightPixels.toLong()
            if (screen <= 0L) return false
            val area = r.width().toLong() * r.height().toLong()
            area < screen * 6 / 10
        } catch (_: Exception) {
            false
        }
    }

    /** Обход дерева нод в глубину: собираем видимый текст и описания. */
    private fun collect(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 24 || sb.length > 4500) return
        val t = node.text?.toString()?.trim()
        if (!t.isNullOrEmpty() && t != "null") {
            sb.append(t).append('\n')
        } else {
            val d = node.contentDescription?.toString()?.trim()
            if (!d.isNullOrEmpty() && d.length > 1) sb.append(d).append('\n')
        }
        for (i in 0 until node.childCount) {
            try { collect(node.getChild(i), sb, depth + 1) } catch (_: Exception) {}
        }
    }

    /** Схлопываем пустые строки и обрезаем до разумного размера. */
    private fun normalize(raw: String): String {
        val lines = raw.split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val distinct = LinkedHashSet(lines)
        val joined = distinct.joinToString("\n")
        return if (joined.length <= 4000) joined else joined.substring(0, 4000)
    }

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        // Мусор от предыдущей сессии сервиса не должен жить вечно.
        latestText = ""
        latestPackage = ""
        latestAt = 0L
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }
}
