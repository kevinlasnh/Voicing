import 'dart:math' show max;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

/// 设备名过长时的「音乐播放器歌名」式缓慢来回滚动文本。
///
/// 设计约束（2026-11-22）：
/// - 只有文本宽度超过可视宽度时才启动动画，短名字保持静态，避免无意义晃动；
/// - 一个周期内：停住展示开头 → 缓慢滚到结尾 → 停住展示结尾 → 缓慢滚回开头，
///   速度与音乐播放器一致，用户能看清完整名称；
/// - 只做水平 `ClipRect + Transform.translate`，不改变行高，保证与右侧
///   更多功能菜单的单元格高度一致。
class AutoScrollText extends StatefulWidget {
  const AutoScrollText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText>
    with SingleTickerProviderStateMixin {
  static const Duration _cycleDuration = Duration(seconds: 12);

  late final AnimationController _controller;
  late final Animation<double> _progress;

  double _overflow = 0;
  double? _scheduledOverflow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _cycleDuration);
    // 12 秒一循环：两端各停约 1.8s，单程滚动约 4.2s，缓慢且可读。
    _progress = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 15),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1),
        weight: 35,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 15),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0),
        weight: 35,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _measureTextWidth(BuildContext context) {
    // Text 实际渲染时会把它继承到的 DefaultTextStyle（Material3 的字体
    // height/letterSpacing/locale 等）与 widget.style 合并；测量必须使用同一份
    // 合成样式，否则长名滚到端点时尾部会被裁掉约一个字母的宽度。
    final effectiveStyle =
        DefaultTextStyle.of(context).style.merge(widget.style);
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: effectiveStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 布局阶段只能测量，不能 setState；把溢出量变化推迟到下一帧，
  /// 再决定启动/停止滚动，避免 build 中触发重建。
  void _scheduleOverflowUpdate(double overflow) {
    if ((overflow - _overflow).abs() < 0.5) {
      return;
    }
    final scheduled = _scheduledOverflow;
    if (scheduled != null && (scheduled - overflow).abs() < 0.5) {
      return;
    }
    _scheduledOverflow = overflow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scheduledOverflow = null;
      if ((overflow - _overflow).abs() < 0.5) {
        return;
      }
      setState(() => _overflow = overflow);
      if (overflow > 0) {
        if (!_controller.isAnimating) {
          _controller.repeat();
        }
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final textWidth = _measureTextWidth(context);
        final overflow = max(0.0, textWidth - viewportWidth);
        _scheduleOverflowUpdate(overflow);

        return ClipRect(
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_overflow * _progress.value, 0),
                child: child,
              );
            },
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              // 关键：父级 SingleChildScrollView 会给「设备行」无界高度约束，
              // OverflowBox 默认 fit=max 会导致 RenderBox infinite size 断言；
              // deferToChild 让自身尺寸跟随文本高度（有限值），行高与右侧菜单一致。
              fit: OverflowBoxFit.deferToChild,
              maxWidth: double.infinity,
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                style: widget.style,
              ),
            ),
          ),
        );
      },
    );
  }
}
