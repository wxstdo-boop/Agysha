package flutter.overlay.window.flutter_overlay_window;

import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.app.PendingIntent;
import android.graphics.Point;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.view.Choreographer;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.Display;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.HashMap;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;

import io.flutter.embedding.android.FlutterTextureView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.FlutterEngineGroup;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.BasicMessageChannel;
import io.flutter.plugin.common.JSONMessageCodec;
import io.flutter.plugin.common.MethodChannel;

public class OverlayService extends Service implements View.OnTouchListener {
    private final int DEFAULT_NAV_BAR_HEIGHT_DP = 48;
    private final int DEFAULT_STATUS_BAR_HEIGHT_DP = 25;

    private Integer mStatusBarHeight = -1;
    private Integer mNavigationBarHeight = -1;
    private Resources mResources;

    public static final String INTENT_EXTRA_IS_CLOSE_WINDOW = "IsCloseWindow";

    private static OverlayService instance;
    public static boolean isRunning = false;
    private WindowManager windowManager = null;
    private FlutterView flutterView;
    private boolean viewAttached = false;
    private MethodChannel flutterChannel;
    private BasicMessageChannel<Object> overlayMessageChannel;
    private int clickableFlag = WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;

    private Handler mAnimationHandler = new Handler();
    private float lastX, lastY;
    private float dragPositionX, dragPositionY;
    // Пока палец ведёт пузырь, окно НЕ перекладываем: сдвигаем уже готовую
    // поверхность транслейтом. updateViewLayout на каждом MOVE заставлял
    // WindowManager заново раскладывать окно с Flutter-поверхностью, и круг
    // догонял палец рывками — со стороны это читалось как «торможенно».
    private int dragBaseX, dragBaseY;
    private float dragTranslationX, dragTranslationY;
    private int lastYPosition;
    private boolean dragging;
    /** Время касания: тап без движения открывает чат. */
    private long tapDownAtMs = 0;
    private static final long TAP_MAX_MS = 1200L;
    // Координаты движения сливаются в один updateViewLayout на vsync.
    // Это не даёт MethodChannel и WindowManager накапливать старые кадры.
    private boolean moveFramePosted = false;
    private int moveFrameGeneration = 0;
    private int pendingMoveX;
    private int pendingMoveY;
    // Окно показываем одним кадром после первого кадра Flutter: пошаговая
    // альфа через updateViewLayout перекладывала окно 60 раз в секунду и
    // давала рывки на входе. Само проявление рисует Flutter (GPU).
    private boolean entryRevealed = false;
    private static final float MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER = 0.8f;
    private Point szWindow = new Point();
    private Timer mTrayAnimationTimer;
    private TrayAnimationTimerTask mTrayTimerTask;

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onDestroy() {
        Log.d("OverLay", "Destroying the overlay window service");
        removeOverlayViewSafely();
        isRunning = false;
        // Гарантированно снимаем уведомление сервиса: на Android < 14
        // foreground-уведомления после уничтожения сервиса иногда "зависают"
        // в шторке — пользователь видел «окошко в уведомлении» после закрытия.
        try {
            NotificationManager nm = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
            nm.cancel(OverlayConstants.NOTIFICATION_ID);
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                stopForeground(true);
            }
        } catch (Exception ignored) {}
        instance = null;
    }

    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        mResources = getApplicationContext().getResources();
        if (intent == null) {
            Log.w("OverlayService", "Ignoring restart without overlay intent");
            stopSelfResult(startId);
            return START_NOT_STICKY;
        }
        int startX = intent.getIntExtra("startX", OverlayConstants.DEFAULT_XY);
        int startY = intent.getIntExtra("startY", OverlayConstants.DEFAULT_XY);
        boolean isCloseWindow = intent.getBooleanExtra(INTENT_EXTRA_IS_CLOSE_WINDOW, false);
        if (isCloseWindow) {
            removeOverlayViewSafely();
            isRunning = false;
            stopSelfResult(startId);
            return START_NOT_STICKY;
        }
        if (windowManager != null || flutterView != null) {
            // Повторный showOverlay может прийти до завершения предыдущего
            // closeOverlay. Снимаем старую view идемпотентно, чтобы Android
            // не получил updateViewLayout для уже удалённого окна.
            removeOverlayViewSafely();
        }
        isRunning = true;
        Log.d("onStartCommand", "Service started");
        FlutterEngine engine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);
        if (engine == null || flutterChannel == null || overlayMessageChannel == null) {
            Log.e("OverlayService", "Overlay engine/channels are not initialized");
            stopSelfResult(startId);
            return START_NOT_STICKY;
        }
        engine.getLifecycleChannel().appIsResumed();
        // TextureView обязан быть ПРОЗРАЧНЫМ: иначе под скруглённой панелью
        // рисуется непрозрачный прямоугольник («квадратные углы»/белый фон
        // за клавиатурой). Окно само по себе PixelFormat.TRANSLUCENT.
        FlutterTextureView textureView = new FlutterTextureView(getApplicationContext());
        textureView.setOpaque(false);
        flutterView = new FlutterView(getApplicationContext(), textureView);
        flutterView.attachToFlutterEngine(FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG));
        // Оверлей не участвует в расчёте системных inset'ов: при показе IME
        // Android не должен добавлять к TextureView светлую незаполненную
        // область и менять его геометрию.
        flutterView.setFitsSystemWindows(false);
        flutterView.setFocusable(true);
        flutterView.setFocusableInTouchMode(true);
        flutterView.setBackgroundColor(Color.TRANSPARENT);
        textureView.setAlpha(1.0f);
        flutterChannel.setMethodCallHandler((call, result) -> {
            try {
                if (call.method.equals("updateFlag")) {
                    Object rawFlag = call.argument("flag");
                    updateOverlayFlag(result, rawFlag == null ? "defaultFlag" : rawFlag.toString());
                } else if (call.method.equals("updateOverlayPosition")) {
                    // Координаты приходят дробными dp — движение плавное, в
                    // пикселях, а не «ступеньками» по 1dp.
                    Object ax = call.argument("x");
                    Object ay = call.argument("y");
                    double x = ax instanceof Number ? ((Number) ax).doubleValue() : 0.0;
                    double y = ay instanceof Number ? ((Number) ay).doubleValue() : 0.0;
                    moveOverlay(x, y, result);
                } else if (call.method.equals("resizeOverlay")) {
                    Object rawWidth = call.argument("width");
                    Object rawHeight = call.argument("height");
                    Object rawDrag = call.argument("enableDrag");
                    int width = rawWidth instanceof Number ? ((Number) rawWidth).intValue() : -1;
                    int height = rawHeight instanceof Number ? ((Number) rawHeight).intValue() : -1;
                    boolean enableDrag = rawDrag instanceof Boolean && (Boolean) rawDrag;
                    resizeOverlay(width, height, enableDrag, result);
                } else {
                    result.notImplemented();
                }
            } catch (RuntimeException error) {
                Log.e("OverlayService", "Overlay method call failed: " + call.method, error);
                result.error("OVERLAY_OPERATION_FAILED", error.getMessage(), null);
            }
        });
        overlayMessageChannel.setMessageHandler((message, reply) -> {
            // Тап по пузырю: сначала поднимаем Agysha на передний план,
            // потом отдаём команду главному движку — он откроет чат Ады.
            // Так пузырь не превращается в мини-окно, а возвращает обычную Аду.
            if (message instanceof java.util.Map
                    && "open_ada_chat".equals(((java.util.Map<?, ?>) message).get("cmd"))) {
                // Просьбу запоминаем в prefs: даже если сервис не сможет
                // поднять задачу (агрессивные прошивки), Dart заберёт метку
                // на следующем resume и откроет чат.
                rememberOpenAdaChat();
                bringAppToFront();
            }
            // Мессенджер главного движка может быть уже отцеплен (приложение
            // выгрузили). Раньше это роняло обработчик — и тап по пузырю
            // терялся молча. Теперь путь «поднять приложение» остаётся живым.
            final BasicMessageChannel<Object> messenger = WindowSetup.messenger;
            if (messenger != null) {
                try {
                    messenger.send(message);
                } catch (RuntimeException error) {
                    Log.w("OverlayService", "Host engine is gone, message dropped", error);
                }
            }
            // Без ответа `shareData` во Flutter висел вечно, а пузырь держал
            // флаг «открываюсь» — второй тап уже ничего не делал.
            if (reply != null) reply.reply(null);
        });
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            windowManager.getDefaultDisplay().getSize(szWindow);
        } else {
            DisplayMetrics displaymetrics = new DisplayMetrics();
            windowManager.getDefaultDisplay().getMetrics(displaymetrics);
            int w = displaymetrics.widthPixels;
            int h = displaymetrics.heightPixels;
            szWindow.set(w, h);
        }
        int dx = startX == OverlayConstants.DEFAULT_XY ? 0 : startX;
        int dy = startY == OverlayConstants.DEFAULT_XY ? -statusBarHeightPx() : startY;
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                // ВАЖНО: стартовое окно тоже конвертируем dp→px, как и в
                // resizeOverlay. Раньше showOverlay(300×520) создавал окно
                // 300×520 ФИЗИЧЕСКИХ px (≈109×189 dp на 2.75-экране) —
                // мини-чат был крошечным: «пара букв и всё сжато».
                WindowSetup.width == -1999 ? -1 : dpToPx(WindowSetup.width),
                WindowSetup.height != -1999 ? dpToPx(WindowSetup.height) : screenHeight(),
                0,
                -statusBarHeightPx(),
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE,
                // БЕЗ FLAG_LAYOUT_INSET_DECOR: при фокусе и открытой клавиатуре
                // этот флаг заставляет систему «ужать» окно по IME-инсетам,
                // и за клавиатурой появлялась белая полоса (фон view без
                // отрисовки). Окно оверлея стоит над всем, инсеты не нужны.
                WindowSetup.flag | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                        | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT
        );
        // До первого кадра Flutter окно прозрачное: иначе пользователь
        // видит пустой прямоугольник, пока движок оверлея стартует.
        final float opacityCeiling = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                && WindowSetup.flag == clickableFlag)
                ? MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER
                : 1f;
        params.alpha = 0f;
        entryRevealed = false;
        params.gravity = WindowSetup.gravity;
        // Оверлей не должен получать resize/pan-анимацию от IME: иначе
        // Android дёргает TextureView при каждом кадре клавиатуры и рисует
        // белую полосу в нижней части окна. Клавиатура принадлежит только
        // фокусируемому TextField, размер оверлея остаётся стабильным.
        params.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING;
        flutterView.setOnTouchListener(this);
        try {
            windowManager.addView(flutterView, params);
            viewAttached = true;
        } catch (RuntimeException error) {
            Log.e("OverlayService", "Unable to attach overlay view", error);
            removeOverlayViewSafely();
            isRunning = false;
            stopSelfResult(startId);
            return START_NOT_STICKY;
        }
        moveOverlay(dx, dy, null);
        // Окно прозрачное: до первого кадра Flutter в нём ничего не
        // нарисовано, а сам пузырь проявляет Dart (выдох альфы и масштаба).
        // Поэтому альфу окна ставим сразу: любая задержка здесь и была тем
        // «пузырь появился не сразу».
        mAnimationHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                revealOverlay(opacityCeiling);
            }
        }, 0);
        return START_NOT_STICKY;
    }

    private void removeOverlayViewSafely() {
        moveFrameGeneration++;
        moveFramePosted = false;
        entryRevealed = false;
        if (mTrayAnimationTimer != null) {
            mTrayAnimationTimer.cancel();
            mTrayAnimationTimer = null;
        }
        if (mTrayTimerTask != null) {
            mTrayTimerTask.cancel();
            mTrayTimerTask = null;
        }
        final FlutterView view = flutterView;
        final WindowManager manager = windowManager;
        flutterView = null;
        windowManager = null;
        viewAttached = false;
        if (manager != null && view != null) {
            try {
                manager.removeViewImmediate(view);
            } catch (IllegalArgumentException | IllegalStateException error) {
                Log.w("OverlayService", "Overlay view was already removed", error);
            }
        }
        if (view != null) {
            try {
                view.detachFromFlutterEngine();
            } catch (RuntimeException error) {
                Log.w("OverlayService", "Overlay view was already detached", error);
            }
        }
    }


    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    private int screenHeight() {
        Display display = windowManager.getDefaultDisplay();
        DisplayMetrics dm = new DisplayMetrics();
        display.getRealMetrics(dm);
        return inPortrait() ?
                dm.heightPixels + statusBarHeightPx() + navigationBarHeightPx()
                :
                dm.heightPixels + statusBarHeightPx();
    }

    private int statusBarHeightPx() {
        if (mStatusBarHeight == -1) {
            int statusBarHeightId = mResources.getIdentifier("status_bar_height", "dimen", "android");

            if (statusBarHeightId > 0) {
                mStatusBarHeight = mResources.getDimensionPixelSize(statusBarHeightId);
            } else {
                mStatusBarHeight = dpToPx(DEFAULT_STATUS_BAR_HEIGHT_DP);
            }
        }

        return mStatusBarHeight;
    }

    int navigationBarHeightPx() {
        if (mNavigationBarHeight == -1) {
            int navBarHeightId = mResources.getIdentifier("navigation_bar_height", "dimen", "android");

            if (navBarHeightId > 0) {
                mNavigationBarHeight = mResources.getDimensionPixelSize(navBarHeightId);
            } else {
                mNavigationBarHeight = dpToPx(DEFAULT_NAV_BAR_HEIGHT_DP);
            }
        }

        return mNavigationBarHeight;
    }


    private void updateOverlayFlag(MethodChannel.Result result, String flag) {
        final WindowManager manager = windowManager;
        final FlutterView view = flutterView;
        if (manager == null || view == null || !viewAttached) {
            result.success(false);
            return;
        }
        try {
            WindowSetup.setFlag(flag);
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) view.getLayoutParams();
            params.flags = WindowSetup.flag | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS |
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN |
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED;
            params.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && WindowSetup.flag == clickableFlag) {
                params.alpha = MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER;
            } else {
                params.alpha = 1;
            }
            manager.updateViewLayout(view, params);
            result.success(true);
        } catch (RuntimeException error) {
            Log.w("OverlayService", "Ignoring flag update for closed overlay", error);
            result.success(false);
        }
    }

    private void resizeOverlay(int width, int height, boolean enableDrag, MethodChannel.Result result) {
        final WindowManager manager = windowManager;
        final FlutterView view = flutterView;
        if (manager == null || view == null || !viewAttached) {
            result.success(false);
            return;
        }
        try {
            // Отбрасываем старую координату, которая могла быть запланирована
            // ещё для предыдущего размера окна.
            moveFrameGeneration++;
            moveFramePosted = false;
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) view.getLayoutParams();
            if (params == null) {
                result.success(false);
                return;
            }
            params.width = (width == -1999 || width == -1) ? -1 : dpToPx(width);
            params.height = (height == 1999 || height == -1) ? -1 : dpToPx(height);
            WindowSetup.enableDrag = enableDrag;
            manager.updateViewLayout(view, params);
            // Пузырь 44 dp катается сам, окно чата — нет.
            // Размер окна больше не влияет на «самокатание»: пузырь качается
            // внутри своего окна силами Flutter.
            // Не вызываем invalidate: он конкурирует с TextureView во время
            // resize и оставляет старый кадр на границе пузыря.
            result.success(true);
        } catch (RuntimeException error) {
            Log.w("OverlayService", "Ignoring resize for closed overlay", error);
            result.success(false);
        }
    }

    private void moveOverlay(double x, double y, MethodChannel.Result result) {
        if (windowManager == null || flutterView == null || !viewAttached) {
            if (result != null) result.success(false);
            return;
        }

        pendingMoveX = (x == -1999.0 || x == -1.0) ? -1 : dpToPxF(x);
        pendingMoveY = dpToPxF(y);
        if (result != null) result.success(true);

        postMoveFrame();
    }

    /// dp → px с дробной точностью: LayoutParams.x — int (пиксели), поэтому
    /// округление даёт шаг в 1 физический пиксель — движение максимально
    /// плавное (раньше был шаг в 1dp ≈ 2.75px на типичных экранах).
    private int dpToPxF(double dp) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, (float) dp, mResources.getDisplayMetrics()));
    }


    public static Map<String, Double> getCurrentPosition() {
        final OverlayService service = instance;
        if (service == null || service.flutterView == null || service.windowManager == null || !service.viewAttached) {
            return null;
        }
        try {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) service.flutterView.getLayoutParams();
            if (params == null) return null;
            Map<String, Double> position = new HashMap<>();
            position.put("x", service.pxToDp(params.x));
            position.put("y", service.pxToDp(params.y));
            return position;
        } catch (RuntimeException error) {
            Log.w("OverlayService", "Unable to read overlay position", error);
            return null;
        }
    }

    public static boolean moveOverlay(int x, int y) {
        final OverlayService service = instance;
        if (service == null || service.flutterView == null || service.windowManager == null || !service.viewAttached) {
            return false;
        }
        try {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) service.flutterView.getLayoutParams();
            if (params == null) return false;
            final int targetX = (x == -1999 || x == -1) ? -1 : service.dpToPx(x);
            final int targetY = service.dpToPx(y);
            params.x = targetX == -1 ? -1 : service.clampToScreenX(targetX, service.flutterView.getWidth());
            params.y = service.clampToScreenY(targetY, service.flutterView.getHeight());
            service.windowManager.updateViewLayout(service.flutterView, params);
            return true;
        } catch (RuntimeException error) {
            Log.w("OverlayService", "Ignoring stale static overlay move", error);
            return false;
        }
    }


    @Override
    public void onCreate() {
        // Get the cached FlutterEngine
        FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);

        if (flutterEngine == null) {
            // Handle the error if engine is not found
            Log.e("OverlayService", "Flutter engine not found, hence creating new flutter engine");
            FlutterEngineGroup engineGroup = new FlutterEngineGroup(this);
            DartExecutor.DartEntrypoint entryPoint = new DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "overlayMain"
            );  // "overlayMain" is custom entry point

            flutterEngine = engineGroup.createAndRunEngine(this, entryPoint);

            // Cache the created FlutterEngine for future use
            FlutterEngineCache.getInstance().put(OverlayConstants.CACHED_TAG, flutterEngine);
            FlutterOverlayWindowPlugin.notifyEngineReady(flutterEngine);
        }

        // Create the MethodChannel with the properly initialized FlutterEngine
        if (flutterEngine != null) {
            flutterChannel = new MethodChannel(flutterEngine.getDartExecutor(), OverlayConstants.OVERLAY_TAG);
            overlayMessageChannel = new BasicMessageChannel(flutterEngine.getDartExecutor(), OverlayConstants.MESSENGER_TAG, JSONMessageCodec.INSTANCE);
        }

        createNotificationChannel();
        Intent notificationIntent = new Intent(this, FlutterOverlayWindowPlugin.class);
        int pendingFlags;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            pendingFlags = PendingIntent.FLAG_IMMUTABLE;
        } else {
            pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent pendingIntent = PendingIntent.getActivity(this,
                0, notificationIntent, pendingFlags);
        final int notifyIcon = getDrawableResourceId("mipmap", "launcher");
        Notification notification = new NotificationCompat.Builder(this, OverlayConstants.CHANNEL_ID)
                .setContentTitle(WindowSetup.overlayTitle)
                .setContentText(WindowSetup.overlayContent)
                .setSmallIcon(notifyIcon == 0 ? R.drawable.notification_icon : notifyIcon)
                .setContentIntent(pendingIntent)
                .setVisibility(NotificationCompat.VISIBILITY_SECRET)
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setOnlyAlertOnce(true)
                .build();
        startForeground(OverlayConstants.NOTIFICATION_ID, notification);
        // Скрыть уведомление мини-окошка (Android 14+): сервис остаётся
        // foreground, но уведомление исчезает из шторки — пользователь
        // просил, чтобы при активном оверлее никакого уведомления не было.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            stopForeground(STOP_FOREGROUND_DETACH);
        }
        // Дополнительная гарантия: на некоторых прошивках (MIUI/HyperOS)
        // detach не убирает уведомление — гасим его и напрямую.
        try {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.cancel(OverlayConstants.NOTIFICATION_ID);
        } catch (Exception ignored) {}
        instance = this;
    }

    /**
     * Поднять приложение из фона. REORDER_TO_FRONT возвращает уже
     * существующую задачу наверх (без второй копии экрана), SINGLE_TOP —
     * чтобы не пересоздавать Activity и не терять состояние чата.
     */
    private void bringAppToFront() {
        // Сначала поднимаем СВОЮ задачу: moveToFront не считается «запуском
        // активности из фона», а на Realme/ColorOS именно это правило глушит
        // startActivity из сервиса — тап по пузырю выглядел как «ничего».
        try {
            ActivityManager manager = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
            if (manager != null) {
                for (ActivityManager.AppTask task : manager.getAppTasks()) {
                    try {
                        task.moveToFront();
                    } catch (RuntimeException error) {
                        Log.w("OverlayService", "moveToFront refused", error);
                    }
                    break;
                }
            }
        } catch (RuntimeException error) {
            Log.w("OverlayService", "Could not raise the task", error);
        }
        try {
            Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
            if (launch == null) return;
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            // Метка для MainActivity: пришли тапом по пузырю, надо открыть
            // чат Ады. Канал оверлея живёт только пока жив главный движок,
            // а intent доходит и до холодного старта.
            launch.putExtra("agysha_open_ada_chat", true);
            startActivity(launch);
        } catch (Exception error) {
            Log.w("OverlayService", "Could not bring app to front", error);
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    OverlayConstants.CHANNEL_ID,
                    "Foreground Service Channel",
                    // IMPORTANCE_NONE — уведомление фонового сервиса окошка
                    // НЕ показывается в шторке вообще (на всех Android):
                    // пользователь просил никаких уведомлений от окошка.
                    NotificationManager.IMPORTANCE_NONE
            );
            serviceChannel.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
            serviceChannel.setShowBadge(false);
            NotificationManager manager = getSystemService(NotificationManager.class);
            assert manager != null;
            manager.createNotificationChannel(serviceChannel);
        }
    }

    private int getDrawableResourceId(String resType, String name) {
        return getApplicationContext().getResources().getIdentifier(String.format("ic_%s", name), resType, getApplicationContext().getPackageName());
    }

    private int dpToPx(int dp) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP,
                Float.parseFloat(dp + ""), mResources.getDisplayMetrics());
    }

    private double pxToDp(int px) {
        return (double) px / mResources.getDisplayMetrics().density;
    }

    private boolean inPortrait() {
        return mResources.getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;
    }

    @Override
    public boolean onTouch(View view, MotionEvent event) {
        if (windowManager == null || flutterView == null || !WindowSetup.enableDrag) {
            return false;
        }
        final WindowManager.LayoutParams params =
                (WindowManager.LayoutParams) flutterView.getLayoutParams();
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                dragging = false;
                lastX = event.getRawX();
                lastY = event.getRawY();
                dragPositionX = params.x;
                dragPositionY = params.y;
                dragBaseX = params.x;
                dragBaseY = params.y;
                dragTranslationX = 0f;
                dragTranslationY = 0f;
                tapDownAtMs = System.currentTimeMillis();
                break;
            case MotionEvent.ACTION_MOVE:
                final float dx = event.getRawX() - lastX;
                final float dy = event.getRawY() - lastY;
                // Порог 3 px, а не 5: на медленном движении окно стартовало
                // с заметной задержкой и «отлипало» от пальца.
                if (!dragging && dx * dx + dy * dy < 9) return false;
                lastX = event.getRawX();
                lastY = event.getRawY();
                final boolean invertX = WindowSetup.gravity == (Gravity.TOP | Gravity.RIGHT)
                        || WindowSetup.gravity == (Gravity.CENTER | Gravity.RIGHT)
                        || WindowSetup.gravity == (Gravity.BOTTOM | Gravity.RIGHT);
                final boolean invertY = WindowSetup.gravity == (Gravity.BOTTOM | Gravity.LEFT)
                        || WindowSetup.gravity == Gravity.BOTTOM
                        || WindowSetup.gravity == (Gravity.BOTTOM | Gravity.RIGHT);
                dragPositionX += dx * (invertX ? -1 : 1);
                dragPositionY += dy * (invertY ? -1 : 1);
                pendingMoveX = Math.round(dragPositionX);
                pendingMoveY = Math.round(dragPositionY);
                dragging = true;
                applyDragTranslation();
                break;
            case MotionEvent.ACTION_UP:
                if (dragging) commitDragTranslation();
                dragging = false;
                lastYPosition = Math.round(dragPositionY);
                // Тап по пузырю открываем и отсюда: Dart-оверлей мог не
                // получить событие (окно только что показалось, движок
                // оверлея ещё поднимается). Пальцем не двигали и держали
                // недолго — значит это тап, а не перетаскивание.
                if (!dragging && tapDownAtMs > 0
                        && System.currentTimeMillis() - tapDownAtMs <= TAP_MAX_MS) {
                    rememberOpenAdaChat();
                    bringAppToFront();
                }
                tapDownAtMs = 0;
                break;
            case MotionEvent.ACTION_CANCEL:
                tapDownAtMs = 0;
                if (dragging) commitDragTranslation();
                dragging = false;
                lastYPosition = Math.round(dragPositionY);
                if (!WindowSetup.positionGravity.equals("none")) {
                    mTrayTimerTask = new TrayAnimationTimerTask();
                    mTrayAnimationTimer = new Timer();
                    mTrayAnimationTimer.schedule(mTrayTimerTask, 0, 25);
                }
                break;
            default:
                break;
        }
        return false;
    }

    /** Пузырь не должен уезжать за край: его всегда можно поймать пальцем. */
    private int clampToScreenX(int x, int viewWidth) {
        final int screen = mResources.getDisplayMetrics().widthPixels;
        return Math.max(0, Math.min(x, Math.max(0, screen - viewWidth)));
    }

    private int clampToScreenY(int y, int viewHeight) {
        final int screen = mResources.getDisplayMetrics().heightPixels;
        return Math.max(0, Math.min(y, Math.max(0, screen - viewHeight)));
    }

    /**
     * Показать окно: одна установка альфы вместо пошаговой анимации.
     * Раньше окно перекладывалось каждый кадр через WindowManager — это
     * дорогая операция, и вход пузыря дёргался. Плавность рисует Flutter.
     */
    private void revealOverlay(float ceiling) {
        if (entryRevealed) return;
        final WindowManager manager = windowManager;
        final FlutterView view = flutterView;
        if (manager == null || view == null || !viewAttached) return;
        final WindowManager.LayoutParams params =
                (WindowManager.LayoutParams) view.getLayoutParams();
        if (params == null) return;
        entryRevealed = true;
        params.alpha = ceiling;
        try {
            manager.updateViewLayout(view, params);
        } catch (RuntimeException error) {
            entryRevealed = false;
        }
    }

    /**
     * Тап по пузырю: запоминаем просьбу «открой чат Ады» в тех же prefs,
     * что читает Dart. Метка переживёт и отказ прошивки поднять задачу:
     * приложение заберёт её на следующем resume.
     */
    private void rememberOpenAdaChat() {
        try {
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean("flutter.pending_open_ada_chat", true)
                    .apply();
        } catch (RuntimeException error) {
            Log.w("OverlayService", "Could not persist open-chat request", error);
        }
    }

    /**
     * Двигаем окно сразу, не откладывая до следующего кадра. Раньше позиция
     * ждала Choreographer: к задержке касания добавлялся целый кадр, и на
     * каждом движении пузырь отставал от пальца — это и читалось как
     * «перемещается тормозно». Записываем только когда позиция реально
     * изменилась, чтобы не гонять лишний layout.
     */
    /**
     * Сдвиг во время жеста: транслейт готовой поверхности, без пересборки окна.
     * Края экрана держим здесь же, чтобы пузырь не «выпал» за границу до
     * отпускания пальца.
     */
    private void applyDragTranslation() {
        final FlutterView view = flutterView;
        if (view == null || !viewAttached) return;
        final int w = Math.max(1, view.getWidth());
        final int h = Math.max(1, view.getHeight());
        final int screenW = mResources.getDisplayMetrics().widthPixels;
        final int screenH = mResources.getDisplayMetrics().heightPixels;
        float tx = pendingMoveX - dragBaseX;
        float ty = pendingMoveY - dragBaseY;
        tx = Math.max(-dragBaseX, Math.min(tx, screenW - w - dragBaseX));
        ty = Math.max(-dragBaseY, Math.min(ty, screenH - h - dragBaseY));
        dragTranslationX = tx;
        dragTranslationY = ty;
        view.setTranslationX(tx);
        view.setTranslationY(ty);
    }

    /**
     * Отпустили: окно встаёт в конечную точку, а сдвиг снимается в том же
     * кадре — визуально пузырь не прыгает.
     */
    private void commitDragTranslation() {
        final FlutterView view = flutterView;
        if (view == null) return;
        pendingMoveX = dragBaseX + Math.round(dragTranslationX);
        pendingMoveY = dragBaseY + Math.round(dragTranslationY);
        applyMoveNow();
        view.setTranslationX(0f);
        view.setTranslationY(0f);
        dragTranslationX = 0f;
        dragTranslationY = 0f;
    }

    private void applyMoveNow() {
        final WindowManager manager = windowManager;
        final FlutterView view = flutterView;
        if (manager == null || view == null || !viewAttached) return;
        try {
            final WindowManager.LayoutParams params =
                    (WindowManager.LayoutParams) view.getLayoutParams();
            if (params == null) return;
            final int targetX = clampToScreenX(pendingMoveX, view.getWidth());
            final int targetY = clampToScreenY(pendingMoveY, view.getHeight());
            if (params.x == targetX && params.y == targetY) return;
            params.x = targetX;
            params.y = targetY;
            manager.updateViewLayout(view, params);
        } catch (RuntimeException error) {
            Log.w("OverlayService", "Ignoring stale overlay move", error);
        }
    }

    private void postMoveFrame() {
        applyMoveNow();
    }

    private class TrayAnimationTimerTask extends TimerTask {
        int mDestX;
        int mDestY;
        WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();

        public TrayAnimationTimerTask() {
            super();
            mDestY = lastYPosition;
            switch (WindowSetup.positionGravity) {
                case "auto":
                    mDestX = (params.x + (flutterView.getWidth() / 2)) <= szWindow.x / 2 ? 0 : szWindow.x - flutterView.getWidth();
                    return;
                case "left":
                    mDestX = 0;
                    return;
                case "right":
                    mDestX = szWindow.x - flutterView.getWidth();
                    return;
                default:
                    mDestX = params.x;
                    mDestY = params.y;
                    break;
            }
        }

        @Override
        public void run() {
            mAnimationHandler.post(() -> {
                params.x = (2 * (params.x - mDestX)) / 3 + mDestX;
                params.y = (2 * (params.y - mDestY)) / 3 + mDestY;
                final WindowManager manager = windowManager;
                final FlutterView view = flutterView;
                if (manager != null && view != null && viewAttached) {
                    try {
                        manager.updateViewLayout(view, params);
                    } catch (RuntimeException error) {
                        Log.w("OverlayService", "Ignoring stale tray animation frame", error);
                        TrayAnimationTimerTask.this.cancel();
                        if (mTrayAnimationTimer != null) mTrayAnimationTimer.cancel();
                    }
                }
                if (Math.abs(params.x - mDestX) < 2 && Math.abs(params.y - mDestY) < 2) {
                    TrayAnimationTimerTask.this.cancel();
                    mTrayAnimationTimer.cancel();
                }
            });
        }
    }


}