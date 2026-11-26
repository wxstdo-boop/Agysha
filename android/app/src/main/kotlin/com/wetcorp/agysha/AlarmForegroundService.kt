package com.wetcorp.agysha

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * «Звонок» будильника: громкое looping-воспроизведение, которое НЕ зависит
 * ни от full-screen-intent права, ни от настроек канала уведомления.
 *
 * Почему он нужен: на этом телефоне (HyperOS/Android 15) замеры показали
 * `USE_FULL_SCREEN_INTENT: ignore` и `FSI CHECK granted=false` — экран
 * будильника открыть нельзя, а звук канала — ОДИН короткий сигнал: если
 * пользователь его не заметил, телефон молчит дальше и он просыпает.
 * Сервис гудит, пока его не остановят (Dart вызывает stopAlarmSound после
 * решения задачи пробуждения) или пока не истечёт [MAX_RING_MS].
 *
 * Пускается ТОЛЬКО из [AlarmReceiver] — то есть из broadcast, полученного по
 * точному AlarmManager-будильнику. Это одно из немногих исключений,
 * разрешающих старт foreground-сервиса из фона на Android 12+.
 */
class AlarmForegroundService : Service() {

    private var player: MediaPlayer? = null
    private var ringtone: android.media.Ringtone? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var vibrating = false

    /// Код (alarm_id.hashCode) будильника, который звонит СЕЙЧАС.
    /// Нужен, чтобы удаление/выключение ОДНОГО будильника глушило звонок
    /// только если звонит именно он, а не любой другой.
    private var ringingCode: Int = -1

    /// id уведомления текущего звонка (совпадает с id будильника). Нужен,
    /// чтобы убрать карточку прошлого звонка, если в ту же минуту звенит
    /// второй будильник, и чтобы не оставить карточку после остановки.
    private var currentNotificationId: Int = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // Регистрируем приёмник остановки: так при остановке остановятся ВСЕ
        // одновременно запущенные экземпляры сервиса, а не только один
        // (ctx.stopService() с простым Intent остановил бы не более одного).
        val i = StopReceiver()
        stopReceiver = i
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(i, IntentFilter(ACTION_STOP), RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(i, IntentFilter(ACTION_STOP))
            }
        } catch (_: Exception) {}
    }


    private var stopReceiver: StopReceiver? = null

    private inner class StopReceiver : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action == ACTION_STOP) {
                // Адресная остановка: если пришёл код будильника, гасим
                // ТОЛЬКО когда звонит именно он. Удаление или выключение
                // одного будильника не должно глушить другой, звенящий
                // параллельно.
                if (intent.hasExtra("ring_code") &&
                    intent.getIntExtra("ring_code", 0) != ringingCode
                ) {
                    return
                }
                stopEverything()
                stopSelf()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            if (intent.hasExtra("ring_code") &&
                intent.getIntExtra("ring_code", 0) != ringingCode
            ) {
                return START_NOT_STICKY
            }
            stopEverything()
            stopSelf(startId)
            return START_NOT_STICKY
        }

        // foreground-уведомление ОБЯЗАНО появиться до истечения ~10 с после
        // startForegroundService — иначе система убьёт процесс.
        startRingingForeground(intent)

        // Запоминаем, чей это звонок: по нему адресная остановка решает,
        // гасить ли текущий звук (см. StopReceiver / stopFor).
        ringingCode = intent?.getIntExtra("ring_code", -1) ?: -1
        val soundName = intent?.getStringExtra("sound_name") ?: "alarm_default"
        val customPath = intent?.getStringExtra("custom_sound_path")
        val vibrate = intent?.getBooleanExtra("vibrate", true) ?: true

        // Новое срабатывание при уже идущем звонке (повтор будильника,
        // догон пропущенного, второй будильник в ту же минуту) — это
        // ОДИН и тот же экземпляр сервиса, и `onStartCommand` придёт
        // снова. Без сброса прежний MediaPlayer терял ссылку и продолжал
        // играть рядом с новым: два звонка накладывались — «будильник
        // двоит». Гасим прошлый звук/вибрацию ПЕРЕД стартом нового.
        resetAudio()

        acquireWakeLock()
        // Передача удержания CPU завершена: сервис надёжно держит свой WakeLock,
        // отпускаем страховку приёмника без зазора для засыпания системы.
        AlarmReceiver.releaseWakeLock()
        playLoop(soundName, customPath)
        if (vibrate) startVibrationLoop()

        // Страховка от «забыли выключить»: телефон не должен звонить вечно.
        handler.postDelayed({ stopEverything() }, MAX_RING_MS)
        return START_NOT_STICKY
    }

    /**
     * Гасит звук и вибрацию текущего звонка, НЕ трогая foreground-статус
     * сервиса и приёмник остановки. Нужен при перезапуске звонка
     * (`onStartCommand` пришёл повторно): иначе старый плеер остаётся
     * играть без ссылки на него, и два звонка накладываются.
     */
    /**
     * Есть ли у приложения право открыть активность по full-screen intent.
     * До Android 14 такого права нет — считаем, что есть.
     */
    private fun canUseFullScreenIntent(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.canUseFullScreenIntent()
        } catch (_: Exception) {
            false
        }
    }

    private fun resetAudio() {
        handler.removeCallbacksAndMessages(null)
        vibrating = false
        fadeOutAndStop(player)
        player = null
        try {
            ringtone?.stop()
        } catch (_: Exception) {}
        ringtone = null
        cancelVibration()
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        wakeLock = null
    }

    /**
     * Отменяет вибрацию ТЕМ ЖЕ экземпляром, на котором она запускалась
     * (см. [stopEverything]): на API 31+ `startVibrationLoop` крутит её через
     * `VibratorManager.defaultVibrator`, и отмена через устаревший
     * `VIBRATOR_SERVICE` на мультивибраторных HyperOS/MIUI брала «другой»
     * мотор — циклическая вибрация продолжала гудеть после выключения.
     */
    @Suppress("DEPRECATION")
    private fun cancelVibration() {
        try {
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                    .defaultVibrator
            } else {
                getSystemService(VIBRATOR_SERVICE) as Vibrator
            }
            vib.cancel()
        } catch (_: Exception) {}
    }

    /**
     * ЕДИНАЯ карточка звонящего будильника.
     *
     * Раньше в шторке висели две: эта (FGS, «Звонок будильника») и вторая из
     * [AlarmReceiver.showNotification] с кнопками. Пользователь видел дубль.
     * Теперь карточку рисует только сервис — с теми же кнопками
     * «Отключить»/«Открыть», full-screen intent и id будильника, поэтому
     * отмена/свайп/остановка работают по тому же id, что и раньше.
     */
    private fun startRingingForeground(intent: Intent?) {
        val title = intent?.getStringExtra("title") ?: "Будильник"
        val body = intent?.getStringExtra("body") ?: ""
        val payload = intent?.getStringExtra("payload") ?: ""
        val fullscreen = intent?.getBooleanExtra("fullscreen", true) ?: true
        val ringId = intent?.getIntExtra("ring_code", 0) ?: 0

        // Канал обязан быть важным: на MIN Android не показывает кнопки и не
        // даёт поднять экран по full-screen intent. Звука у канала нет —
        // звенит MediaPlayer сервиса, вибрацию тоже держит сервис.
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Будильник", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Звонящий будильник: отключить или открыть"
                    setSound(null, null)
                    enableVibration(false)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                },
            )
        }

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_NO_ANIMATION
            putExtra("payload", payload)
            putExtra("alarm_launch", true)
            putExtra("alarm_fullscreen", fullscreen)
        }
        val piFlags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val tap = PendingIntent.getActivity(this, ringId, tapIntent, piFlags)

        val dismissIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_DISMISS
            putExtra("alarm_id", ringId)
        }
        val dismiss = PendingIntent.getBroadcast(
            this,
            ringId + 2000,
            dismissIntent,
            piFlags,
        )

        // id = id будильника (alarm.id.hashCode). По нему же его гасят
        // удаление/выключение и кнопка «Отключить», так что карточка ровно
        // одна и живёт ровно столько, сколько звенит.
        val notifId = if (ringId == 0) NOTIFICATION_ID else ringId
        // defensive: сервис может быть поднят и без свежей проверки права
        val useFullScreen = fullscreen && canUseFullScreenIntent(this)
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(tap)
            .apply { if (useFullScreen) setFullScreenIntent(tap, true) }
            .setOngoing(true)
            .setAutoCancel(false)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setColor(0xFFFDF2F6.toInt())
            .addAction(R.drawable.ic_notification, "Отключить", dismiss)
            .addAction(R.drawable.ic_notification, "Открыть", tap)
            .build()

        // Второй будильник в ту же минуту переиспользует сервис: убираем
        // карточку прошлого, чтобы не копились две.
        if (currentNotificationId != 0 && currentNotificationId != notifId) {
            try {
                nm.cancel(currentNotificationId)
            } catch (_: Exception) {}
        }
        currentNotificationId = notifId

        try {
            ServiceCompat.startForeground(
                this,
                notifId,
                notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                else 0,
            )
        } catch (e: Exception) {
            // На некоторых прошивках specialUse-тип недоступен: звук всё
            // равно нужен, поэтому пробуем без типа.
            try {
                startForeground(notifId, notification)
            } catch (e2: Exception) {
                AlarmLog.write(this, "RING FGS FAILED error=${e2.javaClass.simpleName}")
            }
        }
    }

    // ── Звук ──────────────────────────────────────────────

    private fun playLoop(soundName: String, customPath: String?) {
        // Путь из старых версий мог указать на файл, которого уже нет
        // (кэш file_picker вычищен, источник удалён). Тогда играем
        // ВСТРОЕННЫЙ ресурс по soundName, а не системный дзынь телефона:
        // «свой» файл пропал — но выбранный в приложении звук обязан
        // остаться тем же.
        val usableCustom = customPath?.takeIf { path ->
            if (path.isEmpty()) return@takeIf false
            val f = try {
                if (path.startsWith("file://")) java.io.File(Uri.parse(path).path) else java.io.File(path)
            } catch (_: Exception) {
                return@takeIf false
            }
            f.exists() && f.canRead()
        }
        if (customPath != null && !customPath.isEmpty() && usableCustom == null) {
            AlarmLog.write(this, "RING CUSTOM MISSING path=$customPath → sound=$soundName")
        }
        val uri = try {
            if (usableCustom != null) {
                Uri.parse(if (usableCustom.startsWith("file://")) usableCustom else "file://$usableCustom")
            } else {
                Uri.parse("android.resource://$packageName/raw/$soundName")
            }
        } catch (e: Exception) {
            AlarmLog.write(this, "RING URI EMPTY path=$customPath sound=$soundName error=${e.javaClass.simpleName}")
            null
        }
        if (uri != null) {
            try {
                player = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    setDataSource(this@AlarmForegroundService, uri)
                    isLooping = true
                    prepare()
                    start()
                }
                startVolumeRamp(player)
                AlarmLog.write(this, "RING PLAYER OK uri=$uri")
                return
            } catch (e: Exception) {
                AlarmLog.write(
                    this,
                    "RING PLAYER FAILED uri=$uri error=${e.javaClass.simpleName}",
                )
            }
        }

        // Файл недоступен (пользователь удалил свой рингтон) — системный
        // звук будильника, лишь бы телефон звонил.
        try {
            val def = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val r = RingtoneManager.getRingtone(this, def)
            r?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            r?.play()
            ringtone = r
            // Системный рингтон не зацикливается — перезапускаем, как только
            // он доиграл, иначе звонок кончится через несколько секунд.
            handler.postDelayed(object : Runnable {
                override fun run() {
                    val rt = ringtone ?: return
                    try {
                        if (!rt.isPlaying) rt.play()
                    } catch (_: Exception) {}
                    handler.postDelayed(this, RING_RETRY_MS)
                }
            }, RING_RETRY_MS)
        } catch (e: Exception) {
            AlarmLog.write(this, "RING FALLBACK FAILED error=${e.javaClass.simpleName}")
        }
    }

    /**
     * Плавно гасит плеер и только потом его останавливает.
     *
     * `MediaPlayer.stop()` на полной громкости обрывает волну посреди
     * периода — на Realme это слышно как щелчок/шум в конце звонка
     * («заедание» на выключении). Поэтому громкость уходит в ноль за
     * ~120 мс маленькими шагами и лишь затем плеер останавливается и
     * освобождается. Шаги идут на отдельном Handler: `resetAudio()` в
     * начале следующего звонка чистит основной `handler`, и затухание
     * прошлого плеера не должно обрываться/теряться из-за этого.
     * Ссылка на поле не используется — плеер уже мог быть заменён.
     */
    private fun fadeOutAndStop(mp: MediaPlayer?) {
        if (mp == null) return
        val fadeHandler = Handler(Looper.getMainLooper())
        val steps = 6
        var left = steps
        val step = object : Runnable {
            override fun run() {
                if (left > 0) {
                    val vol = left.toFloat() / steps
                    try {
                        mp.setVolume(vol, vol)
                    } catch (_: Exception) {
                        left = 0
                    }
                    left--
                    fadeHandler.postDelayed(this, 20L)
                    return
                }
                try {
                    mp.stop()
                } catch (_: Exception) {}
                try {
                    mp.release()
                } catch (_: Exception) {}
            }
        }
        step.run()
    }

    /**
     * Плавное нарастание звука (crescendo): стартует с едва слышимого уровня
     * (0.05) и мягко по квадратичной кривой выходит на 100% за 25 секунд.
     * Защищает от утреннего испуга при звонке.
     */
    private fun startVolumeRamp(mp: MediaPlayer?) {
        if (mp == null) return
        var elapsed = 0L
        val rampDurationMs = 25_000L
        val stepMs = 500L
        val startVol = 0.05f
        val targetVol = 1.0f
        try {
            mp.setVolume(startVol, startVol)
        } catch (_: Exception) {}

        val rampRunnable = object : Runnable {
            override fun run() {
                val currentMp = player ?: return
                if (currentMp != mp) return
                elapsed += stepMs
                val progress = (elapsed.toFloat() / rampDurationMs).coerceIn(0.0f, 1.0f)
                val currentVol = startVol + (targetVol - startVol) * (progress * progress)
                try {
                    currentMp.setVolume(currentVol, currentVol)
                } catch (_: Exception) {}
                if (progress < 1.0f) {
                    handler.postDelayed(this, stepMs)
                }
            }
        }
        handler.postDelayed(rampRunnable, stepMs)
    }

    // ── Вибрация ──────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun startVibrationLoop() {
        vibrating = true
        handler.postDelayed(object : Runnable {
            override fun run() {
                if (!vibrating) return
                try {
                    val pattern = longArrayOf(0, 700, 300, 700, 300, 700)
                    val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                            .defaultVibrator
                    } else {
                        getSystemService(VIBRATOR_SERVICE) as Vibrator
                    }
                    // См. AlarmReceiver.doVibrate: без USAGE_ALARM HyperOS
                    // режет вибрацию как «UNKNOWN = OFF».
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        vib.vibrate(
                            VibrationEffect.createWaveform(pattern, -1),
                            android.os.VibrationAttributes.Builder()
                                .setUsage(android.os.VibrationAttributes.USAGE_ALARM)
                                .build(),
                        )
                    } else {
                        vib.vibrate(VibrationEffect.createWaveform(pattern, -1))
                    }
                } catch (_: Exception) {}
                handler.postDelayed(this, VIBRATE_CYCLE_MS)
            }
        }, VIBRATE_CYCLE_MS)
    }

    // ── Удержание CPU ──────────────────────────────────────

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "agysha:alarm_ring")
                .apply { acquire(MAX_RING_MS + 30_000) }
        } catch (_: Exception) {}
    }

    private fun stopEverything() {
        handler.removeCallbacksAndMessages(null)
        vibrating = false
        fadeOutAndStop(player)
        player = null
        try {
            ringtone?.stop()
        } catch (_: Exception) {}
        ringtone = null
        cancelVibration()
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        wakeLock = null
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        // stopForeground снимает только «свою» карточку; на всякий случай
        // гасим по id — иначе после таймаута остаётся висящая табличка.
        if (currentNotificationId != 0) {
            try {
                val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                nm.cancel(currentNotificationId)
            } catch (_: Exception) {}
            currentNotificationId = 0
        }
        stopSelf()
    }

    override fun onDestroy() {
        try {
            stopReceiver?.let { unregisterReceiver(it) }
        } catch (_: Exception) {}
        stopEverything()
        super.onDestroy()
    }

    companion object {
        // v2: прежний канал был IMPORTANCE_MIN («Звонок будильника») — на нём
        // Android не показывает кнопки. Важность канала не меняется после
        // создания, поэтому это НОВЫЙ канал, а не правка старого.
        private const val CHANNEL = "agysha_alarm_ring_v2"
        private const val NOTIFICATION_ID = 66667

        /** Долже звонить, чем «проспать», но и не вечно. */
        private const val MAX_RING_MS = 5 * 60_000L
        private const val RING_RETRY_MS = 1_500L
        private const val VIBRATE_CYCLE_MS = 3_500L

        const val ACTION_STOP = "com.wetcorp.agysha.action.STOP_RING"

        /**
         * Запустить звонок. Вызывается из [AlarmReceiver] (broadcast по
         * точному будильнику) и из «Теста» будильника.
         */
        /**
         * Запустить звонок.
         *
         * Возвращает `false`, если система отказала в старте — на Android 12+
         * это обычное дело для фоновых сервисов (исключения жёстко
         * перечислены платформой). Принимающая сторона обязана подстраховать
         * звук уведомлением, иначе будильник окажется немым.
         */
        fun start(
            ctx: Context,
            soundName: String,
            customPath: String?,
            vibrate: Boolean,
            title: String,
            body: String,
            payload: String,
            ringCode: Int = -1,
            fullscreen: Boolean = true,
        ): Boolean {
            val i = Intent(ctx, AlarmForegroundService::class.java).apply {
                putExtra("sound_name", soundName)
                putExtra("vibrate", vibrate)
                putExtra("title", title)
                putExtra("body", body)
                putExtra("payload", payload)
                putExtra("ring_code", ringCode)
                putExtra("fullscreen", fullscreen)
                if (!customPath.isNullOrEmpty()) putExtra("custom_sound_path", customPath)
            }
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(i)
                } else {
                    ctx.startService(i)
                }
                true
            } catch (e: Exception) {
                AlarmLog.write(ctx, "RING START REJECTED error=${e.javaClass.simpleName}: ${e.message}")
                false
            }
        }

        /**
         * Остановить звонок (после решения задачи пробуждения / отмены).
         *
         * Всё новое — широковещательная остановка. [ctx.stopService] с
         * простым Intent остановит НЕ БОЛЕЕ одного из запущенных
         * экземпляров сервиса, и тогда второй звонок продолжит проигрываться
         * после первого (именно это было в описанной проблеме). Отправляем
         * [ACTION_STOP] широковещательно; каждый зарегистрированный в
         * сервисе экземпляр захватит его и вызовет [stopEverything] + [stopSelf].
         */
        fun stop(ctx: Context) {
            try {
                val i = Intent(ACTION_STOP).apply {
                    `package` = ctx.packageName
                }
                ctx.sendBroadcast(i)
                ctx.stopService(Intent(ctx, AlarmForegroundService::class.java))
                AlarmReceiver.cancelVibration(ctx)
            } catch (_: Exception) {}
        }

        /**
         * Остановить звонок КОНКРЕТНОГО будильника ([ringCode] =
         * `alarm_id.hashCode`). Нужно, когда пользователь удаляет или
         * выключает будильник ПОКА он звонит: отмена AlarmManager и
         * уведомления звонок не гасит — сервис продолжал бы играть до
         * [MAX_RING_MS] (5 минут). Сервис сам решит, гасить ли текущий звук,
         * сравнив [ringCode] со своим (см. StopReceiver).
         */
        fun stopFor(ctx: Context, ringCode: Int) {
            try {
                val i = Intent(ACTION_STOP).apply {
                    `package` = ctx.packageName
                    putExtra("ring_code", ringCode)
                }
                ctx.sendBroadcast(i)
                ctx.stopService(Intent(ctx, AlarmForegroundService::class.java))
            } catch (_: Exception) {}
        }
    }
}
