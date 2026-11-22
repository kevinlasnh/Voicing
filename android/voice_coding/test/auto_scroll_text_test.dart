import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicing/auto_scroll_text.dart';

/// `AutoScrollText` 的布局/滚动回归测试（2026-11-22 新增）。
///
/// 背景：该组件曾被塞在 `Positioned(width 无 height) -> ConstrainedBox(maxHeight)
/// -> SingleChildScrollView -> Column -> Row -> Expanded` 的真实菜单约束链里，
/// 当时 `OverflowBox` 用默认 fit=max，在无界高度下会抛
/// "RenderBox was given an infinite size during layout"，但 analyze/纯 Dart 测试
/// 完全发现不了。本测试用同样的祖先约束链，确保：
/// 1. 设备行不抛布局异常，且行高与右侧更多功能菜单行一致；
/// 2. 短名字保持静止，长名字会缓慢滚动（音乐播放器歌名效果）。
void main() {
  const double padding = 14;
  const double iconSize = 18;
  const double gap = 8;

  // 与 main.dart 同几何的菜单行（测试不依赖 Material，降低编译开销）。
  Widget menuRow({required Widget textChild, Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.all(padding),
      child: Row(
        children: [
          const SizedBox(width: iconSize, height: iconSize),
          const SizedBox(width: gap),
          Expanded(child: textChild),
        ],
      ),
    );
  }

  Widget deviceRow({required Widget textChild, Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.all(padding),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF5CB87A),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: iconSize),
              child: RepaintBoundary(child: textChild),
            ),
          ),
        ],
      ),
    );
  }

  /// 与 main.dart 设备子菜单完全一致的约束链：高度无界是最关键的回归条件。
  Widget menuAncestor({required Widget child}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 600)),
        child: SizedBox(
          width: 400,
          height: 600,
          child: Stack(
            children: [
              Positioned(
                left: 16,
                top: 100,
                width: 320,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D3B37),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [child],
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

  testWidgets(
      'device row lays out without infinite size and matches menu row height',
      (tester) async {
    await tester.pumpWidget(
      menuAncestor(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            deviceRow(
              key: const ValueKey('device-row'),
              textChild: const AutoScrollText(
                text: 'A Very Long Desktop Computer Name That Overflows',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            menuRow(
              key: const ValueKey('menu-row'),
              textChild: const Text(
                '设备选择',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final deviceSize = tester.getSize(find.byKey(const ValueKey('device-row')));
    final menuSize = tester.getSize(find.byKey(const ValueKey('menu-row')));
    // 关键断言：设备行与右侧菜单行严格等高（测试字体的 label 行高可能 >18，
    // 所以不写死 46，只要求两行相等且不小于 padding+icon 的基础高度）。
    expect(deviceSize.height, menuSize.height);
    expect(deviceSize.height, greaterThanOrEqualTo(padding * 2 + iconSize));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('short name stays static while long name slowly scrolls',
      (tester) async {
    await tester.pumpWidget(
      menuAncestor(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            deviceRow(
              key: const ValueKey('short-row'),
              textChild: const AutoScrollText(
                text: 'PC',
                style: TextStyle(fontSize: 15),
              ),
            ),
            deviceRow(
              key: const ValueKey('long-row'),
              textChild: const AutoScrollText(
                text:
                    'A Very Long Desktop Computer Name That Overflows The Row',
                style: TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
    // 先让 post-frame 的溢出测量完成，再记录初始位置。
    await tester.pump();
    final shortBefore =
        tester.getTopLeft(find.text('PC', skipOffstage: false)).dx;
    final longBefore = tester
        .getTopLeft(
          find.text(
            'A Very Long Desktop Computer Name That Overflows The Row',
            skipOffstage: false,
          ),
        )
        .dx;

    await tester.pump(const Duration(seconds: 4));
    final shortAfter =
        tester.getTopLeft(find.text('PC', skipOffstage: false)).dx;
    final longAfter = tester
        .getTopLeft(
          find.text(
            'A Very Long Desktop Computer Name That Overflows The Row',
            skipOffstage: false,
          ),
        )
        .dx;

    expect(tester.takeException(), isNull);
    expect(shortAfter, shortBefore, reason: '短名字不应滚动');
    expect(longAfter, lessThan(longBefore - 1), reason: '长名字应向左滚动');

    // 滚到端点后文本尾部不能超出可视区：测量样式必须与 Text 实际继承的
    // DefaultTextStyle 合并，否则端点会静默裁掉约一个字符（QA Low-1 回归）。
    await tester.pump(const Duration(seconds: 2));
    final rowRect = tester.getRect(find.byKey(const ValueKey('long-row')));
    final viewportRight = rowRect.right - padding;
    final longTailRight = tester
        .getTopRight(
          find.text(
            'A Very Long Desktop Computer Name That Overflows The Row',
            skipOffstage: false,
          ),
        )
        .dx;
    expect(
      longTailRight,
      lessThanOrEqualTo(viewportRight + 0.5),
      reason: '滚动端点文本尾部不应超出可视区',
    );

    // 停掉动画并卸载子树，避免测试结束时报 pending frame。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
