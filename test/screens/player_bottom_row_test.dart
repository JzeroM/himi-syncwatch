import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_bottom_row.dart';

Widget _host(PlayerBottomRow row, {double width = 600}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: 80, child: row),
        ),
      ),
    );

const _transportKey = ValueKey('t');
const _trailingKey = ValueKey('r');
const _leadingKey = ValueKey('l');

List<Widget> _transport() => const [
      SizedBox(key: _transportKey, width: 120, height: 40),
    ];
List<Widget> _trailing() => const [
      SizedBox(key: _trailingKey, width: 80, height: 40),
    ];

void main() {
  testWidgets('centered=false：传输组置左、trailing 贴右', (tester) async {
    await tester.pumpWidget(_host(PlayerBottomRow(
      transport: _transport(),
      leading: const [SizedBox(key: _leadingKey, width: 40, height: 40)],
      trailing: _trailing(),
    )));

    final rowLeft = tester.getTopLeft(find.byType(PlayerBottomRow)).dx;
    final tLeft = tester.getTopLeft(find.byKey(_transportKey)).dx;
    final lLeft = tester.getTopLeft(find.byKey(_leadingKey)).dx;
    final rRight = tester.getTopRight(find.byKey(_trailingKey)).dx;
    expect(tLeft, rowLeft, reason: '传输组贴左');
    expect(lLeft, greaterThan(tLeft), reason: 'leading 在传输组右侧');
    expect(rRight, rowLeft + 600, reason: 'trailing 贴右');
  });

  testWidgets('centered=true：传输组精确水平居中、trailing 贴右', (tester) async {
    await tester.pumpWidget(_host(PlayerBottomRow(
      centered: true,
      transport: _transport(),
      trailing: _trailing(),
    )));

    final rowLeft = tester.getTopLeft(find.byType(PlayerBottomRow)).dx;
    final tCenter = tester.getCenter(find.byKey(_transportKey)).dx;
    final rRight = tester.getTopRight(find.byKey(_trailingKey)).dx;
    expect(tCenter, rowLeft + 300, reason: '传输组中心 == 容器中线');
    expect(rRight, rowLeft + 600, reason: 'trailing 贴右');
  });

  testWidgets('centered=true：极窄容器下 trailing 缩放防溢出', (tester) async {
    await tester.pumpWidget(_host(
      PlayerBottomRow(
        centered: true,
        transport: const [
          SizedBox(key: _transportKey, width: 100, height: 40),
        ],
        trailing: const [
          SizedBox(key: _trailingKey, width: 120, height: 40),
        ],
      ),
      width: 200,
    ));

    // 无溢出异常即可（FittedBox scaleDown 生效）
    expect(tester.takeException(), isNull);
    final rowLeft = tester.getTopLeft(find.byType(PlayerBottomRow)).dx;
    final tCenter = tester.getCenter(find.byKey(_transportKey)).dx;
    expect(tCenter, rowLeft + 100, reason: '传输组仍居中');
  });
}
