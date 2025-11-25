import 'dart:math' as math;
import 'dart:ui';

import '../simulation/ant.dart';

class AntSpriteStyle {
  const AntSpriteStyle({
    required this.lengthFactor,
    required this.widthFactor,
    required this.headFactor,
    required this.thoraxFactor,
    required this.abdomenFactor,
    required this.legLengthFactor,
    required this.antennaLengthFactor,
    required this.selectionScale,
  });

  final double lengthFactor;
  final double widthFactor;
  final double headFactor;
  final double thoraxFactor;
  final double abdomenFactor;
  final double legLengthFactor;
  final double antennaLengthFactor;
  final double selectionScale;
}

const _defaultStyle = AntSpriteStyle(
  lengthFactor: 0.95,
  widthFactor: 0.35,
  headFactor: 0.2,
  thoraxFactor: 0.25,
  abdomenFactor: 0.55,
  legLengthFactor: 0.55,
  antennaLengthFactor: 0.35,
  selectionScale: 0.6,
);

const Map<AntCaste, AntSpriteStyle> antSpriteStyles = {
  AntCaste.worker: _defaultStyle,
  AntCaste.soldier: AntSpriteStyle(
    lengthFactor: 1.05,
    widthFactor: 0.4,
    headFactor: 0.22,
    thoraxFactor: 0.28,
    abdomenFactor: 0.5,
    legLengthFactor: 0.6,
    antennaLengthFactor: 0.4,
    selectionScale: 0.65,
  ),
  AntCaste.nurse: AntSpriteStyle(
    lengthFactor: 0.85,
    widthFactor: 0.33,
    headFactor: 0.22,
    thoraxFactor: 0.25,
    abdomenFactor: 0.53,
    legLengthFactor: 0.5,
    antennaLengthFactor: 0.3,
    selectionScale: 0.55,
  ),
  AntCaste.drone: AntSpriteStyle(
    lengthFactor: 0.9,
    widthFactor: 0.34,
    headFactor: 0.23,
    thoraxFactor: 0.27,
    abdomenFactor: 0.5,
    legLengthFactor: 0.55,
    antennaLengthFactor: 0.35,
    selectionScale: 0.6,
  ),
  AntCaste.princess: AntSpriteStyle(
    lengthFactor: 1.1,
    widthFactor: 0.38,
    headFactor: 0.2,
    thoraxFactor: 0.25,
    abdomenFactor: 0.55,
    legLengthFactor: 0.58,
    antennaLengthFactor: 0.35,
    selectionScale: 0.7,
  ),
  AntCaste.queen: AntSpriteStyle(
    lengthFactor: 1.4,
    widthFactor: 0.5,
    headFactor: 0.18,
    thoraxFactor: 0.3,
    abdomenFactor: 0.52,
    legLengthFactor: 0.65,
    antennaLengthFactor: 0.35,
    selectionScale: 0.85,
  ),
  AntCaste.builder: AntSpriteStyle(
    lengthFactor: 1.0,
    widthFactor: 0.36,
    headFactor: 0.22,
    thoraxFactor: 0.27,
    abdomenFactor: 0.51,
    legLengthFactor: 0.58,
    antennaLengthFactor: 0.35,
    selectionScale: 0.62,
  ),
};

class ColonyPalette {
  const ColonyPalette({required this.body, required this.carrying});

  final Color body;
  final Color carrying;
}

const List<ColonyPalette> colonyPalettes = [
  ColonyPalette(body: Color(0xFFF44336), carrying: Color(0xFFEF9A9A)),
  ColonyPalette(body: Color(0xFFFFEB3B), carrying: Color(0xFFFFF59D)),
  ColonyPalette(body: Color(0xFF2196F3), carrying: Color(0xFF64B5F6)),
  ColonyPalette(body: Color(0xFFFFFFFF), carrying: Color(0xFF9E9E9E)),
];

Color bodyColorForColony(int colonyId, {required bool carrying}) {
  final palette = colonyPalettes[colonyId.clamp(0, colonyPalettes.length - 1)];
  return carrying ? palette.carrying : palette.body;
}

const Color _soldierAccentColor = Color(0xFFEF6C00);
const Color _nurseAccentColor = Color(0xFFF48FB1);
const Color _princessAccentColor = Color(0xFF8E24AA);

Color? accentColorForCaste(AntCaste caste) {
  switch (caste) {
    case AntCaste.soldier:
      return _soldierAccentColor;
    case AntCaste.nurse:
      return _nurseAccentColor;
    case AntCaste.princess:
      return _princessAccentColor;
    default:
      return null;
  }
}

void drawAntSprite({
  required Canvas canvas,
  required Offset center,
  required double angle,
  required double cellSize,
  required AntCaste caste,
  required Color bodyColor,
  Color? accentColor,
}) {
  final style = antSpriteStyles[caste] ?? _defaultStyle;
  final totalLength = cellSize * style.lengthFactor;
  final bodyWidth = cellSize * style.widthFactor;
  final headLen = totalLength * style.headFactor;
  final thoraxLen = totalLength * style.thoraxFactor;
  final abdomenLen = totalLength * style.abdomenFactor;
  final legLength = cellSize * style.legLengthFactor;
  final antennaLength = cellSize * style.antennaLengthFactor;

  final bodyPaint = Paint()
    ..color = bodyColor
    ..style = PaintingStyle.fill;
  final strokePaint = Paint()
    ..color = bodyColor.withValues(alpha: 0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, cellSize * 0.03)
    ..strokeCap = StrokeCap.round;
  final legPaint = Paint()
    ..color = bodyColor.withValues(alpha: 0.8)
    ..strokeWidth = math.max(1, cellSize * 0.025)
    ..strokeCap = StrokeCap.round;
  final antennaPaint = Paint()
    ..color = bodyColor.withValues(alpha: 0.8)
    ..strokeWidth = math.max(1, cellSize * 0.02)
    ..strokeCap = StrokeCap.round;
  final accentPaint = accentColor == null
      ? null
      : (Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, cellSize * 0.05)
          ..strokeCap = StrokeCap.round);

  var cursor = -totalLength / 2;
  final abdomenCenter = Offset(cursor + abdomenLen / 2, 0);
  cursor += abdomenLen;
  final thoraxCenter = Offset(cursor + thoraxLen / 2, 0);
  cursor += thoraxLen;
  final headCenter = Offset(cursor + headLen / 2, 0);

  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(angle);

  void drawSegment(Offset segmentCenter, double length, double width) {
    final rect = Rect.fromCenter(
      center: segmentCenter,
      width: width,
      height: length,
    );
    canvas.drawOval(rect, bodyPaint);
    canvas.drawOval(rect, strokePaint);
  }

  drawSegment(abdomenCenter, abdomenLen, bodyWidth * 1.2);
  drawSegment(thoraxCenter, thoraxLen, bodyWidth);
  drawSegment(headCenter, headLen, bodyWidth * 0.85);

  if (accentPaint != null) {
    final accentRect = Rect.fromCenter(
      center: thoraxCenter,
      width: bodyWidth * 1.4,
      height: thoraxLen * 0.9,
    );
    canvas.drawOval(accentRect, accentPaint);
  }

  // Legs (3 per side) anchored to thorax
  const forwardAngles = [0.75, 0.25, -0.35];
  for (final side in [-1, 1]) {
    for (var i = 0; i < 3; i++) {
      final t = (i + 0.5) / 3;
      final baseX = thoraxCenter.dx - thoraxLen / 2 + t * thoraxLen;
      final baseY = thoraxCenter.dy + side * bodyWidth * 0.45;
      final base = Offset(baseX, baseY);
      final baseAngle = forwardAngles[i] * side;
      final elbowOut = Offset(
        baseX + math.cos(baseAngle) * (legLength * 0.5),
        baseY + math.sin(baseAngle) * (legLength * 0.5),
      );
      final retractAngle = (math.pi * 0.65) * -side;
      final tip = Offset(
        elbowOut.dx + math.cos(retractAngle) * (legLength * 0.6),
        elbowOut.dy + math.sin(retractAngle) * (legLength * 0.6),
      );
      canvas.drawLine(base, elbowOut, legPaint);
      canvas.drawLine(elbowOut, tip, legPaint);
    }
  }

  // Antennae
  final headFront = Offset(headCenter.dx + headLen / 2, 0);
  for (final side in [-1, 1]) {
    final baseAngle = (math.pi / 5) * side;
    final elbow = Offset(
      headFront.dx + math.cos(baseAngle) * (antennaLength * 0.6),
      headFront.dy + math.sin(baseAngle) * (antennaLength * 0.6),
    );
    final tipAngle = baseAngle - side * 0.4;
    final tip = Offset(
      elbow.dx + math.cos(tipAngle) * (antennaLength * 0.4),
      elbow.dy + math.sin(tipAngle) * (antennaLength * 0.4),
    );
    canvas.drawLine(headFront, elbow, antennaPaint);
    canvas.drawLine(elbow, tip, antennaPaint);
  }

  canvas.restore();
}

double selectionRadiusForCaste(AntCaste caste, double cellSize) {
  final style = antSpriteStyles[caste] ?? _defaultStyle;
  return style.selectionScale * cellSize;
}
