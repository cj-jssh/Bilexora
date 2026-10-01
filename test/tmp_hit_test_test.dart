import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final longText =
      'Paragraph has enough words to wrap onto several lines so the box '
      'spans nearly full width, leaving trailing white after each wrapped '
      'line. Lorem ipsum dolor sit amet consectetur adipiscing elit sed do ';

  Widget textLine(String text, Key key) => LayoutBuilder(builder: (context, cc) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cc.maxWidth),
          child: SelectableText(
            text,
            key: key,
            style: const TextStyle(fontSize: 20, height: 1.9),
            maxLines: null,
          ),
        );
      });

  final k1 = GlobalKey();
  final k2 = GlobalKey();

  Widget buildApp() {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                textLine('First short sentence.', k1),
                const SizedBox(height: 12),
                textLine(longText, k2),
                const SizedBox(height: 12),
                textLine('Last line here.', GlobalKey()),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool pointOnGlyph(Offset globalPos) {
    for (final editable in find
        .byType(SelectableText)
        .evaluate()
        .map((e) => e.renderObject)
        .whereType<RenderEditable>()) {
      // local position
      final local = editable.globalToLocal(globalPos);
      // ignore if outside this editable's box
      if (!(Offset.zero & editable.size).contains(local)) continue;
      // check nearest glyph box
      final pos = editable.getPositionForPoint(globalPos);
      final range = TextRange(start: pos.offset, end: pos.offset + 1);
      debugPrint('  editable size=${editable.size} global=${editable.localToGlobal(Offset.zero)}');
      debugPrint('  tap local=${editable.globalToLocal(globalPos)} pos=${pos.offset}');
      final boxes = editable.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end));
      debugPrint('  boxes=$boxes');
      for (final b in boxes) {
        final rect = editable.localToGlobal(Offset(b.left, b.top));
        final r = Rect.fromLTRB(rect.dx, rect.dy, rect.dx+b.right-b.left, rect.dy+b.bottom-b.top);
        if (r.contains(globalPos)) return true;
      }
    }
    return false;
  }

  testWidgets('glyph detection', (tester) async {
    await tester.pumpWidget(buildApp());

    debugPrint('[字形@30,30] onGlyph=${pointOnGlyph(const Offset(30, 30))}');
    debugPrint('[后半行空白@450,150] onGlyph=${pointOnGlyph(const Offset(450, 150))}');
    debugPrint('[行间距@450,260] onGlyph=${pointOnGlyph(const Offset(450, 260))}');
  });
}
