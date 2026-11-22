import 'dart:async';
import 'dart:convert';
import 'dart:math' show max, min, pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'app_theme.dart';
import 'auto_scroll_text.dart';
import 'connection_recovery_policy.dart';
import 'voicing_connection_controller.dart';

void main() {
  runApp(const VoicingApp());
}

class VoicingApp extends StatelessWidget {
  const VoicingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voicing',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const double _headerControlHeight = 48;
  static const double _statusTextHorizontalOffset = 2;
  static const double _headerTextVerticalOffset = 0;
  static const double _menuWarmupOpacity = 0.001;
  static const Duration _qrOpenAfterKeyboardDelay = Duration(milliseconds: 280);
  static const EventChannel _keyboardInsetsChannel =
      EventChannel('voicing/keyboard_insets');

  final GlobalKey _menuButtonKey = GlobalKey();

  late final VoicingConnectionController _controller;
  late final MobileScannerController _qrScannerController;
  late final AnimationController _menuAnimationController;
  late final Animation<double> _menuSlideAnimation;
  late final Animation<double> _menuFadeAnimation;
  late final AnimationController _deviceMenuAnimationController;
  late final Animation<double> _deviceMenuSlideAnimation;
  late final Animation<double> _deviceMenuFadeAnimation;
  StreamSubscription<dynamic>? _keyboardInsetsSubscription;

  bool _showMenu = false;
  bool _menuOverlayMounted = false;
  bool _prepaintMenuOverlay = false;
  // 2026-11-22 多设备：更多功能操作里的「设备选择」向左弹出的二级菜单状态。
  bool _showDeviceMenu = false;
  bool _deviceMenuOverlayMounted = false;
  bool _qrLocking = false;
  double? _nativeKeyboardInset;
  Size _qrScannerLayoutSize = Size.zero;
  DateTime? _qrScannerEnteredAt;
  DateTime? _lastQrErrorShownAt;
  ({BarcodeCapture capture, Barcode barcode, String rawValue})? _pendingQrLock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = VoicingConnectionController();
    _controller.addListener(_handleControllerUpdate);
    _qrScannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      formats: const [BarcodeFormat.qrCode],
    );

    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _menuSlideAnimation = CurvedAnimation(
      parent: _menuAnimationController,
      curve: Curves.easeOutCubic,
    );
    _menuFadeAnimation = CurvedAnimation(
      parent: _menuAnimationController,
      curve: Curves.easeOut,
    );
    // 设备选择二级菜单：与主菜单同款淡入 + 轻微位移，方向改为从右侧滑入
    // （视觉上它是从主菜单左侧展开，所以起点在右往左靠拢）。
    _deviceMenuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _deviceMenuSlideAnimation = CurvedAnimation(
      parent: _deviceMenuAnimationController,
      curve: Curves.easeOutCubic,
    );
    _deviceMenuFadeAnimation = CurvedAnimation(
      parent: _deviceMenuAnimationController,
      curve: Curves.easeOut,
    );

    _controller.initialize();
    _listenToNativeKeyboardInsets();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _menuOverlayMounted = true;
          _prepaintMenuOverlay = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _prepaintMenuOverlay = false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleControllerUpdate);
    _controller.dispose();
    _qrScannerController.dispose();
    _menuAnimationController.dispose();
    _deviceMenuAnimationController.dispose();
    _keyboardInsetsSubscription?.cancel();
    super.dispose();
  }

  void _listenToNativeKeyboardInsets() {
    _keyboardInsetsSubscription =
        _keyboardInsetsChannel.receiveBroadcastStream().listen(
      (event) {
        if (!mounted || event is! num) {
          return;
        }
        final nextInset = event.toDouble();
        if (_nativeKeyboardInset != null &&
            (nextInset - _nativeKeyboardInset!).abs() < 0.25) {
          return;
        }
        setState(() => _nativeKeyboardInset = nextInset);
      },
      onError: (_) {
        if (mounted) {
          setState(() => _nativeKeyboardInset = null);
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleLifecycleState(state);
  }

  void _handleControllerUpdate() {
    if (mounted) {
      if (_controller.qrScanMode && _qrScannerEnteredAt == null) {
        _qrScannerEnteredAt = DateTime.now();
      } else if (!_controller.qrScanMode) {
        _qrScannerEnteredAt = null;
        _pendingQrLock = null;
        _qrLocking = false;
      }
      setState(() {});
    }
  }

  void _toggleMenu() {
    if (_showMenu) {
      _closeMenu();
      return;
    }

    setState(() => _showMenu = true);
    _menuAnimationController.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showMenu) {
        _menuAnimationController.forward(from: 0);
      }
    });
  }

  void _closeMenu() {
    _showDeviceMenu = false;
    _deviceMenuOverlayMounted = false;
    _deviceMenuAnimationController.value = 0;
    _menuAnimationController.reverse().then((_) {
      if (mounted) {
        setState(() => _showMenu = false);
      }
    });
  }

  /// 打开/关闭「设备选择」二级菜单（点击外部时先关二级菜单）。
  void _toggleDeviceMenu() {
    if (_showDeviceMenu) {
      _closeDeviceMenu();
      return;
    }
    setState(() {
      _showDeviceMenu = true;
      _deviceMenuOverlayMounted = true;
    });
    _deviceMenuAnimationController.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showDeviceMenu) {
        _deviceMenuAnimationController.forward(from: 0);
      }
    });
  }

  void _closeDeviceMenu() {
    _deviceMenuAnimationController.reverse().then((_) {
      if (mounted) {
        // 动画结束后必须把二级菜单从树里真正移除：Opacity 为 0 时仍会参与
        // 命中测试，若不卸载，收起后原地仍能点到不可见的设备行。
        setState(() {
          _showDeviceMenu = false;
          _deviceMenuOverlayMounted = false;
        });
      }
    });
  }

  void _handleMenuBackdropTap() {
    // 二级菜单打开时，第一次点遮罩只收起二级菜单，主菜单保持展开，
    // 避免用户误触后整个「更多功能操作」消失。
    if (_showDeviceMenu) {
      _closeDeviceMenu();
      return;
    }
    _closeMenu();
  }

  void _handleDeviceSelected(String deviceKey) {
    // 与右侧更多功能菜单的其他项一致：点选设备只切换发送目标，主菜单和
    // 子菜单都保持展开（选中高亮由 controller 通知触发重建），只有点击
    // 非菜单区域（backdrop）才会收起菜单。
    _controller.selectDevice(deviceKey);
  }

  void _refreshConnection() {
    _controller.refreshConnection();
  }

  void _recallLastText() {
    _controller.recallLastText();
  }

  Future<void> _openQrScannerFromMenu() async {
    final hadKeyboardOpen =
        (_nativeKeyboardInset ?? MediaQuery.of(context).viewInsets.bottom) > 0;

    _closeMenu();
    FocusManager.instance.primaryFocus?.unfocus();

    if (hadKeyboardOpen) {
      await Future<void>.delayed(_qrOpenAfterKeyboardDelay);
    }
    if (!mounted) {
      return;
    }

    _controller.enterQrScanMode();
  }

  Future<void> _showManualServerDialog() async {
    final ipController = TextEditingController(text: _controller.serverIp);
    final portController = TextEditingController(
      text: _controller.serverPort.toString(),
    );

    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          String? errorText;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('手动输入 IP'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: ipController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'PC IP',
                        hintText: '192.168.1.23',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: portController,
                      decoration: const InputDecoration(labelText: '端口'),
                      keyboardType: TextInputType.number,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          errorText!,
                          style: AppTextStyles.hint.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final ip = ipController.text.trim();
                      final port = int.tryParse(portController.text.trim());
                      if (ip.isEmpty || port == null || port <= 0) {
                        setDialogState(() => errorText = '请输入有效的 IP 和端口');
                        return;
                      }
                      await _controller.setManualServer(ip: ip, port: port);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text('连接'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      ipController.dispose();
      portController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset =
        _nativeKeyboardInset ?? MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md + keyboardInset,
              ),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: AppSpacing.componentGap),
                  Expanded(child: _buildInputArea()),
                  const SizedBox(height: AppSpacing.md),
                  _buildEnterHint(),
                ],
              ),
            ),
          ),
          if (_showMenu || _menuOverlayMounted)
            _buildDropdownMenuOverlay(isOpen: _showMenu),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final bool showSyncWarning =
        _controller.displayStatus == ConnectionStatus.connected &&
            !_controller.syncEnabled;

    late final Color connectionDotColor;
    String connectionText;
    if (_controller.displayStatus == ConnectionStatus.connecting) {
      connectionDotColor = AppColors.warning;
      connectionText = '连接中...';
    } else if (_controller.displayStatus == ConnectionStatus.connected) {
      connectionDotColor =
          showSyncWarning ? AppColors.warning : AppColors.success;
      connectionText = showSyncWarning ? '同步关闭' : '已连接';
    } else {
      connectionDotColor = AppColors.error;
      connectionText = '未连接';
    }
    return Row(
      children: [
        Expanded(
          child: Container(
            height: _headerControlHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.componentPadding,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildStatusDot(connectionDotColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Transform.translate(
                    offset: const Offset(
                      _statusTextHorizontalOffset,
                      _headerTextVerticalOffset,
                    ),
                    child: Text(
                      connectionText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        color: connectionDotColor,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.componentGap),
        Expanded(child: _buildMenuButton()),
      ],
    );
  }

  Widget _buildMenuButton() {
    return Material(
      key: _menuButtonKey,
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
        splashColor: const Color(0x1AFFFFFF),
        highlightColor: const Color(0x0DFFFFFF),
        onTap: _toggleMenu,
        child: Container(
          height: _headerControlHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.componentPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _menuAnimationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _menuAnimationController.value * (pi / 2),
                    child: child,
                  );
                },
                child: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, _headerTextVerticalOffset),
                  child: Text(
                    '更多功能操作',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: AppTextStyles.label.copyWith(height: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownMenuOverlay({required bool isOpen}) {
    final renderBox =
        _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return const SizedBox.shrink();
    }

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    return SizedBox.expand(
      child: IgnorePointer(
        ignoring: !isOpen,
        child: AnimatedBuilder(
          animation: _menuFadeAnimation,
          builder: (context, child) {
            final opacity = isOpen
                ? _menuFadeAnimation.value
                : _prepaintMenuOverlay
                    ? _menuWarmupOpacity
                    : 0.0;
            return Opacity(
              opacity: opacity,
              child: child,
            );
          },
          child: GestureDetector(
            onTap: _handleMenuBackdropTap,
            behavior: HitTestBehavior.translucent,
            child: Container(
              color: Colors.black54,
              child: Stack(
                children: [
                  Positioned(
                    left: offset.dx,
                    top: offset.dy + size.height + AppSpacing.sm,
                    width: size.width,
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _menuSlideAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(
                              0,
                              -20 * (1 - _menuSlideAnimation.value),
                            ),
                            child: Opacity(
                              opacity: _menuSlideAnimation.value,
                              child: child,
                            ),
                          );
                        },
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.borderRadius,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildMenuItem(
                                  icon: Icons.refresh,
                                  text: '刷新连接',
                                  onTap: () {
                                    _refreshConnection();
                                  },
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(
                                      AppSpacing.borderRadius,
                                    ),
                                    topRight: Radius.circular(
                                      AppSpacing.borderRadius,
                                    ),
                                  ),
                                ),
                                const Divider(
                                  height: 1,
                                  color: AppColors.divider,
                                  indent: AppSpacing.md,
                                  endIndent: AppSpacing.md,
                                ),
                                _buildMenuItem(
                                  icon: Icons.undo,
                                  text: '撤回上次输入',
                                  onTap: () {
                                    _recallLastText();
                                  },
                                ),
                                const Divider(
                                  height: 1,
                                  color: AppColors.divider,
                                  indent: AppSpacing.md,
                                  endIndent: AppSpacing.md,
                                ),
                                _buildToggleMenuItem(
                                  icon: Icons.keyboard_return,
                                  text: '自动 Enter',
                                  isEnabled: _controller.autoEnterEnabled,
                                  onTap: () {
                                    _controller.toggleAutoEnter();
                                  },
                                ),
                                const Divider(
                                  height: 1,
                                  color: AppColors.divider,
                                  indent: AppSpacing.md,
                                  endIndent: AppSpacing.md,
                                ),
                                _buildMenuItem(
                                  icon: Icons.qr_code_scanner,
                                  text: '扫码连接',
                                  onTap: _openQrScannerFromMenu,
                                ),
                                const Divider(
                                  height: 1,
                                  color: AppColors.divider,
                                  indent: AppSpacing.md,
                                  endIndent: AppSpacing.md,
                                ),
                                // 2026-11-22 多设备：设备选择放在扫码连接下方，
                                // 点击后向左侧展开二级菜单，风格与主菜单一致。
                                _buildDeviceSelectorMenuItem(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_deviceMenuOverlayMounted)
                    _buildDeviceSelectionSubmenu(offset: offset, size: size),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 「设备选择」主菜单项：与刷新连接/撤回上次输入等行完全同款，
  /// 只有统一小图标 + 四字文本，不显示当前设备名、也没有额外箭头，
  /// 从而保证每一格高度与左右内边距完全一致。
  Widget _buildDeviceSelectorMenuItem() {
    return _buildMenuItem(
      icon: Icons.devices_other,
      text: '设备选择',
      onTap: _toggleDeviceMenu,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(AppSpacing.borderRadius),
        bottomRight: Radius.circular(AppSpacing.borderRadius),
      ),
    );
  }

  /// 设备选择二级菜单：从主菜单左侧展开，列出全部已配对设备及其连接状态。
  Widget _buildDeviceSelectionSubmenu({
    required Offset offset,
    required Size size,
  }) {
    // 与主界面「已连接」和「更多功能操作」两个格子之间的间距一致，
    // 视觉上左侧子菜单就是右侧菜单的对称邻居。
    final left = max(
      offset.dx - size.width - AppSpacing.componentGap,
      AppSpacing.md,
    );
    return Positioned(
      left: left,
      top: offset.dy + size.height + AppSpacing.sm,
      width: size.width,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _deviceMenuSlideAnimation,
            _deviceMenuFadeAnimation,
          ]),
          builder: (context, child) {
            // 从右往左轻微滑入（视觉上从主菜单左侧“推出来”），与主菜单的
            // 上滑 + 淡入保持同一套动效语言。
            return Transform.translate(
              offset: Offset(14 * (1 - _deviceMenuSlideAnimation.value), 0),
              child: Opacity(
                opacity: _deviceMenuFadeAnimation.value,
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _buildDeviceSelectionRows(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDeviceSelectionRows() {
    final devices = _controller.pairedDevices;
    if (devices.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.componentPadding),
          child: Row(
            children: [
              const Icon(
                Icons.devices_other,
                color: AppColors.textHint,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '暂无已配对设备，请先扫码连接',
                  // 用 label 的字号/行高（只换颜色与字重）保证空态行与
                  // 右侧菜单项高度一致，不出现半像素级参差。
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final rows = <Widget>[];
    for (var index = 0; index < devices.length; index++) {
      if (index > 0) {
        rows.add(
          const Divider(
            height: 1,
            color: AppColors.divider,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
          ),
        );
      }
      rows.add(
        _buildDeviceSelectionRow(
          devices[index],
          isFirst: index == 0,
          isLast: index == devices.length - 1,
        ),
      );
    }
    return rows;
  }

  Widget _buildDeviceSelectionRow(
    PairedDeviceState device, {
    required bool isFirst,
    required bool isLast,
  }) {
    final statusColor = _deviceStatusColor(device);
    // 当前发送目标用「常驻高亮」表示：颜色与右侧菜单点击时的 highlightColor
    // 完全一致，因此用户对「选中」和「按下」的视觉反馈是同一套语言。
    // 不额外放对勾/删除按钮，每格只保留状态灯 + 设备名。
    final highlightColor =
        device.isActive ? const Color(0x0DFFFFFF) : Colors.transparent;
    // 面板本身是圆角容器；高亮块必须跟着同样的圆角并裁剪，否则首/尾行的
    // 高亮会盖住面板圆角、露出方形边。
    final rowBorderRadius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? AppSpacing.borderRadius : 0),
      topRight: Radius.circular(isFirst ? AppSpacing.borderRadius : 0),
      bottomLeft: Radius.circular(isLast ? AppSpacing.borderRadius : 0),
      bottomRight: Radius.circular(isLast ? AppSpacing.borderRadius : 0),
    );
    return Material(
      color: highlightColor,
      shape: RoundedRectangleBorder(borderRadius: rowBorderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handleDeviceSelected(device.deviceKey),
        onLongPress: () => _confirmRemoveDevice(device),
        splashColor: const Color(0x1AFFFFFF),
        // 选中行已经有常驻高亮底色，按压时不再叠加同一层 highlight，
        // 保证「选中行按压」与「普通行按压」的视觉亮度一致。
        highlightColor:
            device.isActive ? Colors.transparent : const Color(0x0DFFFFFF),
        customBorder: RoundedRectangleBorder(borderRadius: rowBorderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.componentPadding),
          child: Row(
            children: [
              _buildStatusDot(statusColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                // 顶部「已连接」格的文字有 +2px 光学位移，这里复刻同一偏移，
                // 保证「灯→文字」视觉间距与顶部格完全一致；minHeight 18 用于
                // 兼容个别字体行高小于菜单图标的场景，实际等高主要来自设备行
                // 与菜单行都使用 AppTextStyles.label 的同一套文本行高。
                child: Transform.translate(
                  offset: const Offset(_statusTextHorizontalOffset, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 18),
                    child: RepaintBoundary(
                      child: AutoScrollText(
                        key: ValueKey(device.deviceKey),
                        text: device.displayName,
                        style: AppTextStyles.label,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 移除已配对设备前的确认框（风格与手动 IP 对话框一致）。
  Future<void> _confirmRemoveDevice(PairedDeviceState device) async {
    if (!mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除已配对设备？'),
          content: Text(
            '确定要从设备选择中删除 ${device.displayName} 吗？删除后下次使用需要重新扫码配对。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    // 对话框打开期间设备可能刚好完成 legacy key -> device_id 身份升级，
    // 此时快照里的 deviceKey 已过期；按当前列表重新解析一次再删。
    final currentKey = _resolveCurrentDeviceKey(device);
    if (currentKey != null) {
      _controller.removeDevice(currentKey);
    }
  }

  String? _resolveCurrentDeviceKey(PairedDeviceState snapshot) {
    final devices = _controller.pairedDevices;
    for (final device in devices) {
      if (device.deviceKey == snapshot.deviceKey) {
        return device.deviceKey;
      }
    }
    for (final device in devices) {
      if (snapshot.server.deviceId.isNotEmpty &&
          device.server.deviceId == snapshot.server.deviceId) {
        return device.deviceKey;
      }
      if (device.server.ip == snapshot.server.ip) {
        return device.deviceKey;
      }
    }
    return null;
  }

  /// 设备行状态颜色：与头部状态点同一套语义（已连接/连接中/未连接），
  /// 同步关闭时用警告色，避免用户以为消息发不出去是设备问题。
  Color _deviceStatusColor(PairedDeviceState device) {
    if (device.status == ConnectionStatus.connected) {
      return device.syncEnabled ? AppColors.success : AppColors.warning;
    }
    if (device.status == ConnectionStatus.connecting) {
      return AppColors.warning;
    }
    return AppColors.error;
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    BorderRadius? borderRadius,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0x1AFFFFFF),
        highlightColor: const Color(0x0DFFFFFF),
        customBorder: borderRadius != null
            ? RoundedRectangleBorder(borderRadius: borderRadius)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.componentPadding),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textPrimary, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleMenuItem({
    required IconData icon,
    required String text,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0x1AFFFFFF),
        highlightColor: const Color(0x0DFFFFFF),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.componentPadding),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textPrimary, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.label,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildToggleIcon(isEnabled),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleIcon(bool isEnabled) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: Icon(
        isEnabled ? Icons.check : Icons.close,
        key: ValueKey(isEnabled),
        color: isEnabled ? AppColors.success : AppColors.error,
        size: 18,
      ),
    );
  }

  Widget _buildStatusDot(Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 4,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    if (_controller.qrScanMode) {
      return _buildQrScannerArea();
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
      ),
      padding: const EdgeInsets.all(AppSpacing.componentPadding),
      child: TextField(
        controller: _controller.textController,
        maxLines: null,
        expands: true,
        decoration: const InputDecoration(
          hintText: '输入文字或使用语音...',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
          isDense: true,
          hintStyle: TextStyle(color: AppColors.textHint),
        ),
        style: const TextStyle(
          fontSize: 16,
          color: AppColors.textPrimary,
        ),
        cursorColor: AppColors.primary,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => unawaited(_controller.sendText()),
      ),
    );
  }

  Widget _buildQrScannerArea() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scannerSize = constraints.biggest;
          _qrScannerLayoutSize = scannerSize;
          final lockedCorners = _controller.lastQrCorners;
          final qrPairingSucceeded = _controller.qrPairingSucceeded;
          final qrPairingFailed = _controller.qrPairingFailed;
          final qrResult = qrPairingFailed
              ? _QrScanResult.failure
              : qrPairingSucceeded
                  ? _QrScanResult.success
                  : _QrScanResult.none;

          return Stack(
            children: [
              // Layer 0: 真实相机预览
              Positioned.fill(
                child: MobileScanner(
                  controller: _qrScannerController,
                  onDetect: _onQrDetected,
                  errorBuilder: (context, error, child) {
                    return _buildQrScannerError(error);
                  },
                ),
              ),
              // Layer 1: 成功态轻遮罩
              if (lockedCorners != null)
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 0.16),
                    duration: const Duration(milliseconds: 160),
                    builder: (context, opacity, _) {
                      return ColoredBox(
                        color: Colors.black.withOpacity(opacity),
                      );
                    },
                  ),
                ),
              // Layer 2: 单 painter 承载待机呼吸 + 白到绿 + 四角吸附
              Positioned.fill(
                child: _QrScanOverlay(
                  targetCorners: lockedCorners,
                  scannerSize: scannerSize,
                  result: qrResult,
                ),
              ),
              // 右上角关闭按钮
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _controller.exitQrScanMode(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onQrDetected(BarcodeCapture capture) {
    if (_qrLocking || _controller.lastQrCorners != null) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final rawValue = barcode.rawValue!;

    final validationError = _validateVoicingQrPayload(rawValue);
    if (validationError != null) {
      _showQrScanError(validationError);
      return;
    }

    final enteredAt = _qrScannerEnteredAt;
    if (enteredAt == null) return;

    final elapsed = DateTime.now().difference(enteredAt);
    const settleDelay = Duration(milliseconds: 1000);
    if (elapsed < settleDelay) {
      _pendingQrLock = (capture: capture, barcode: barcode, rawValue: rawValue);
      Future.delayed(settleDelay - elapsed, _tryConsumePendingQrLock);
      return;
    }

    _lockVoicingQr(capture, barcode, rawValue);
  }

  void _tryConsumePendingQrLock() {
    if (!mounted ||
        !_controller.qrScanMode ||
        _qrLocking ||
        _pendingQrLock == null) {
      return;
    }

    final pending = _pendingQrLock!;
    _pendingQrLock = null;
    _lockVoicingQr(pending.capture, pending.barcode, pending.rawValue);
  }

  void _lockVoicingQr(
    BarcodeCapture capture,
    Barcode barcode,
    String rawValue,
  ) {
    if (_qrLocking || _controller.lastQrCorners != null) return;
    _qrLocking = true;

    final mappedCorners = _mapBarcodeCornersToScanner(
      barcode.corners,
      captureSize: capture.size,
    );
    final offsets = mappedCorners ??
        _centerFrameCorners(_qrScannerLayoutSize, _QrScanOverlay.defaultSize);
    _controller.handleQrDetected(rawValue, offsets);
  }

  String? _validateVoicingQrPayload(String rawValue) {
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) {
        return '二维码损坏，请重试';
      }
      final map = Map<String, dynamic>.from(decoded);
      if (map['type'] != 'voicing') {
        return '这不是 Voicing 的二维码';
      }
      if (map['v'] != 1) {
        return '二维码版本不兼容，请升级应用';
      }
      return null;
    } catch (_) {
      return '二维码损坏，请重试';
    }
  }

  void _showQrScanError(String message) {
    final now = DateTime.now();
    final lastShownAt = _lastQrErrorShownAt;
    if (lastShownAt != null &&
        now.difference(lastShownAt) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastQrErrorShownAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  Widget _buildQrScannerError(MobileScannerException error) {
    final bool permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: AppColors.inputFill,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              permissionDenied ? Icons.videocam_off : Icons.error_outline,
              color: AppColors.textHint,
              size: 36,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              permissionDenied ? '权限被拒绝，请去系统设置开启相机权限' : '相机不可用，请重试',
              textAlign: TextAlign.center,
              style: AppTextStyles.label,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () {
                _controller.exitQrScanMode();
                _showManualServerDialog();
              },
              child: const Text('手动输入 IP'),
            ),
          ],
        ),
      ),
    );
  }

  List<Offset>? _mapBarcodeCornersToScanner(
    List<Offset> corners, {
    required Size captureSize,
  }) {
    if (corners.length != 4 || _qrScannerLayoutSize.isEmpty) {
      return null;
    }

    final sourceSize =
        !captureSize.isEmpty ? captureSize : _qrScannerController.value.size;
    if (sourceSize.isEmpty) {
      return null;
    }

    final scale = max(
      _qrScannerLayoutSize.width / sourceSize.width,
      _qrScannerLayoutSize.height / sourceSize.height,
    );
    final fittedWidth = sourceSize.width * scale;
    final fittedHeight = sourceSize.height * scale;
    final dx = (_qrScannerLayoutSize.width - fittedWidth) / 2;
    final dy = (_qrScannerLayoutSize.height - fittedHeight) / 2;

    return corners.map((corner) {
      final x = (corner.dx * scale + dx).clamp(
        0.0,
        _qrScannerLayoutSize.width,
      );
      final y = (corner.dy * scale + dy).clamp(
        0.0,
        _qrScannerLayoutSize.height,
      );
      return Offset(x, y);
    }).toList(growable: false);
  }

  Widget _buildEnterHint() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: AppColors.divider),
        const SizedBox(height: AppSpacing.sm),
        const Center(
          child: Text(
            '语音自动发送 · 请扫二维码连接设备',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
        ),
      ],
    );
  }
}

List<Offset> _centerFrameCorners(Size size, double frameSize) {
  if (size.isEmpty) {
    return const [
      Offset.zero,
      Offset.zero,
      Offset.zero,
      Offset.zero,
    ];
  }

  final left = (size.width - frameSize) / 2;
  final top = (size.height - frameSize) / 2;
  final right = left + frameSize;
  final bottom = top + frameSize;
  return [
    Offset(left, top),
    Offset(right, top),
    Offset(right, bottom),
    Offset(left, bottom),
  ];
}

class _QrScanOverlay extends StatefulWidget {
  const _QrScanOverlay({
    required this.targetCorners,
    required this.scannerSize,
    required this.result,
  });

  static const double defaultSize = 180;

  final List<Offset>? targetCorners;
  final Size scannerSize;
  final _QrScanResult result;

  @override
  State<_QrScanOverlay> createState() => _QrScanOverlayState();
}

class _QrScanOverlayState extends State<_QrScanOverlay>
    with TickerProviderStateMixin {
  static const Duration _lockDuration = Duration(milliseconds: 680);
  static const Duration _resultColorDuration = Duration(milliseconds: 520);

  late final AnimationController _ctrl;
  late final AnimationController _resultCtrl;
  late List<Offset> _fromCorners;
  late List<Offset> _toCorners;
  List<Offset>? _lastTargetCorners;
  bool _locked = false;
  _QrScanResult _lastResult = _QrScanResult.none;

  @override
  void initState() {
    super.initState();
    _fromCorners = _idleCorners(widget.scannerSize, 0);
    _toCorners = _fromCorners;
    _ctrl = AnimationController(
      duration: _lockDuration,
      vsync: this,
    )..repeat();
    _resultCtrl = AnimationController(
      duration: _resultColorDuration,
      vsync: this,
    );
    _syncTarget(initial: true);
    _syncResult(initial: true);
  }

  @override
  void didUpdateWidget(covariant _QrScanOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTarget();
    _syncResult();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  void _syncTarget({bool initial = false}) {
    if (widget.targetCorners == null) {
      if (_locked || initial) {
        _locked = false;
        _lastTargetCorners = null;
        _lastResult = _QrScanResult.none;
        _resultCtrl.reset();
        _fromCorners = _idleCorners(widget.scannerSize, _ctrl.value);
        _toCorners = _fromCorners;
        _ctrl
          ..duration = const Duration(milliseconds: 2000)
          ..repeat();
      }
      return;
    }

    if (_lastTargetCorners == widget.targetCorners && !initial) {
      return;
    }

    _fromCorners = _locked
        ? _interpolateCorners(_fromCorners, _toCorners, _ctrl.value)
        : _idleCorners(widget.scannerSize, _ctrl.value);
    _toCorners = _normalizedCorners(widget.targetCorners!, widget.scannerSize);
    _lastTargetCorners = widget.targetCorners;
    _locked = true;
    _ctrl
      ..duration = _lockDuration
      ..forward(from: 0);
  }

  void _syncResult({bool initial = false}) {
    if (_lastResult == widget.result && !initial) {
      return;
    }

    _lastResult = widget.result;
    if (widget.result == _QrScanResult.none) {
      _resultCtrl.reset();
      return;
    }

    _resultCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_ctrl, _resultCtrl]),
        builder: (context, _) {
          final progress = _locked
              ? Curves.easeInOutCubicEmphasized.transform(_ctrl.value)
              : 0.0;
          final resultProgress =
              Curves.easeInOutCubic.transform(_resultCtrl.value);
          return CustomPaint(
            painter: _QrScanOverlayPainter(
              fromCorners: _fromCorners,
              toCorners: _toCorners,
              idleCorners: _idleCorners(widget.scannerSize, _ctrl.value),
              progress: progress,
              locked: _locked,
              result: widget.result,
              resultProgress: resultProgress,
            ),
          );
        },
      ),
    );
  }
}

List<Offset> _idleCorners(Size scannerSize, double animationValue) {
  final phase = (sin(animationValue * 2 * pi - pi / 2) + 1) / 2;
  final size = _QrScanOverlay.defaultSize * (0.94 + 0.04 * phase);
  return _centerFrameCorners(scannerSize, size);
}

List<Offset> _normalizedCorners(List<Offset> corners, Size bounds) {
  if (corners.length != 4 || bounds.isEmpty) {
    return _centerFrameCorners(bounds, _QrScanOverlay.defaultSize);
  }

  final center = Offset(
    corners.map((corner) => corner.dx).reduce((a, b) => a + b) / corners.length,
    corners.map((corner) => corner.dy).reduce((a, b) => a + b) / corners.length,
  );

  return corners.map((corner) {
    final direction = corner - center;
    final expandedCorner = direction.distance == 0
        ? corner
        : corner + direction / direction.distance * 8;
    return Offset(
      expandedCorner.dx.clamp(0.0, bounds.width),
      expandedCorner.dy.clamp(0.0, bounds.height),
    );
  }).toList(growable: false);
}

List<Offset> _interpolateCorners(
  List<Offset> from,
  List<Offset> to,
  double progress,
) {
  if (from.length != 4 || to.length != 4) {
    return to;
  }

  return List<Offset>.generate(
    4,
    (index) => Offset.lerp(from[index], to[index], progress) ?? to[index],
    growable: false,
  );
}

void _drawRoundedCorner(
  Canvas canvas,
  Paint paint,
  Offset corner,
  Offset dirA,
  Offset dirB,
  double armLen,
  double radius,
) {
  if (armLen <= 0 || radius <= 0) {
    return;
  }

  final start = corner + dirA * armLen;
  final arcStart = corner + dirA * radius;
  final arcEnd = corner + dirB * radius;
  final end = corner + dirB * armLen;

  final path = Path()
    ..moveTo(start.dx, start.dy)
    ..lineTo(arcStart.dx, arcStart.dy)
    ..quadraticBezierTo(corner.dx, corner.dy, arcEnd.dx, arcEnd.dy)
    ..lineTo(end.dx, end.dy);
  canvas.drawPath(path, paint);
}

enum _QrScanResult { none, success, failure }

class _QrScanOverlayPainter extends CustomPainter {
  _QrScanOverlayPainter({
    required this.fromCorners,
    required this.toCorners,
    required this.idleCorners,
    required this.progress,
    required this.locked,
    required this.result,
    required this.resultProgress,
  });

  final List<Offset> fromCorners;
  final List<Offset> toCorners;
  final List<Offset> idleCorners;
  final double progress;
  final bool locked;
  final _QrScanResult result;
  final double resultProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final corners = locked
        ? _interpolateCorners(fromCorners, toCorners, progress)
        : idleCorners;
    if (corners.length != 4) {
      return;
    }

    final targetColor = switch (result) {
      _QrScanResult.success => AppColors.success,
      _QrScanResult.failure => AppColors.error,
      _QrScanResult.none => AppColors.textPrimary,
    };
    final color = Color.lerp(
      AppColors.textPrimary,
      targetColor,
      result == _QrScanResult.none ? 0.0 : resultProgress,
    )!;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = locked ? 3.5 : 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    _drawCornerSet(canvas, corners, linePaint);
  }

  void _drawCornerSet(Canvas canvas, List<Offset> corners, Paint paint) {
    _drawCorner(canvas, paint, corners[0], corners[1], corners[3]);
    _drawCorner(canvas, paint, corners[1], corners[0], corners[2]);
    _drawCorner(canvas, paint, corners[2], corners[1], corners[3]);
    _drawCorner(canvas, paint, corners[3], corners[0], corners[2]);
  }

  void _drawCorner(
    Canvas canvas,
    Paint paint,
    Offset corner,
    Offset edgeA,
    Offset edgeB,
  ) {
    final lenA = (edgeA - corner).distance;
    final lenB = (edgeB - corner).distance;
    if (lenA == 0 || lenB == 0) {
      return;
    }

    final armA = min(32.0, lenA * 0.3);
    final armB = min(32.0, lenB * 0.3);
    final radius = min(10.0, min(armA, armB) * 0.5);
    final dirA = (edgeA - corner) / lenA;
    final dirB = (edgeB - corner) / lenB;

    _drawRoundedCorner(
        canvas, paint, corner, dirA, dirB, min(armA, armB), radius);
  }

  @override
  bool shouldRepaint(covariant _QrScanOverlayPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.locked != locked ||
        oldDelegate.result != result ||
        oldDelegate.resultProgress != resultProgress ||
        oldDelegate.fromCorners != fromCorners ||
        oldDelegate.toCorners != toCorners ||
        oldDelegate.idleCorners != idleCorners;
  }
}
