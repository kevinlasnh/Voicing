import 'dart:math' show pi;

import 'package:flutter/material.dart';

import 'app_theme.dart';
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
  final GlobalKey _menuButtonKey = GlobalKey();

  late final VoicingConnectionController _controller;
  late final AnimationController _menuAnimationController;
  late final Animation<double> _menuSlideAnimation;
  late final Animation<double> _menuFadeAnimation;

  bool _showMenu = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = VoicingConnectionController();
    _controller.addListener(_handleControllerUpdate);

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

    _controller.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleControllerUpdate);
    _controller.dispose();
    _menuAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleLifecycleState(state);
  }

  void _handleControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleMenu() {
    if (_showMenu) {
      _closeMenu();
      return;
    }

    setState(() => _showMenu = true);
    _menuAnimationController.forward();
  }

  void _closeMenu() {
    _menuAnimationController.reverse().then((_) {
      if (mounted) {
        setState(() => _showMenu = false);
      }
    });
  }

  void _refreshConnection() {
    _controller.refreshConnection();
  }

  void _recallLastText() {
    _controller.recallLastText();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
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
          if (_showMenu) _buildDropdownMenuOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final bool showSyncWarning =
        _controller.status == ConnectionStatus.connected &&
            !_controller.syncEnabled;

    late final Color connectionDotColor;
    late final String connectionText;
    if (_controller.status == ConnectionStatus.connecting) {
      connectionDotColor = AppColors.warning;
      connectionText = '连接中...';
    } else if (_controller.status == ConnectionStatus.connected) {
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
            padding: const EdgeInsets.all(AppSpacing.componentPadding),
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
            ),
            child: Row(
              children: [
                _buildStatusDot(connectionDotColor),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  connectionText,
                  style: AppTextStyles.label.copyWith(
                    color: connectionDotColor,
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
          padding: const EdgeInsets.all(AppSpacing.componentPadding),
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
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
              const Expanded(
                child: Text(
                  '更多功能操作',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownMenuOverlay() {
    final renderBox =
        _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return const SizedBox.shrink();
    }

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    return SizedBox.expand(
      child: FadeTransition(
        opacity: _menuFadeAnimation,
        child: GestureDetector(
          onTap: _closeMenu,
          behavior: HitTestBehavior.translucent,
          child: Container(
            color: Colors.black54,
            child: Stack(
              children: [
                Positioned(
                  left: offset.dx,
                  top: offset.dy + size.height + AppSpacing.sm,
                  width: size.width,
                  child: AnimatedBuilder(
                    animation: _menuSlideAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset:
                            Offset(0, -20 * (1 - _menuSlideAnimation.value)),
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
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(AppSpacing.borderRadius),
                                topRight: Radius.circular(AppSpacing.borderRadius),
                              ),
                              child: _buildMenuItem(
                                icon: Icons.refresh,
                                text: '刷新连接',
                                onTap: () {
                                  _closeMenu();
                                  _refreshConnection();
                                },
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
                                _closeMenu();
                                _recallLastText();
                              },
                            ),
                            const Divider(
                              height: 1,
                              color: AppColors.divider,
                              indent: AppSpacing.md,
                              endIndent: AppSpacing.md,
                            ),
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(AppSpacing.borderRadius),
                                bottomRight: Radius.circular(AppSpacing.borderRadius),
                              ),
                              child: _buildToggleMenuItem(
                                icon: Icons.keyboard_return,
                                text: '自动 Enter',
                                isEnabled: _controller.autoEnterEnabled,
                                onTap: () {
                                  _controller.toggleAutoEnter();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
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
          ],
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
    return InkWell(
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
    );
  }

  Widget _buildToggleIcon(bool isEnabled) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 250),
      tween: Tween<double>(begin: 0.0, end: isEnabled ? 1.0 : 0.0),
      builder: (context, value, child) {
        final color = Color.lerp(
          AppColors.error,
          AppColors.success,
          value,
        )!;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: Icon(
            isEnabled ? Icons.check : Icons.close,
            key: ValueKey(isEnabled),
            color: color,
            size: 18,
          ),
        );
      },
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
        onSubmitted: (_) => _controller.sendText(),
      ),
    );
  }

  Widget _buildEnterHint() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: AppColors.divider),
        const SizedBox(height: AppSpacing.sm),
        const Center(
          child: Text(
            '语音自动发送 · 回车手动发送',
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
