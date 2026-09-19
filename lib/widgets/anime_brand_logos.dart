import 'package:flutter/material.dart';

/// Official AniList logo widget drawn with crisp vector paths.
class AniListLogo extends StatelessWidget {
  final double size;
  final bool withBackground;

  const AniListLogo({
    super.key,
    this.size = 36,
    this.withBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final logo = CustomPaint(
      size: Size(size, size),
      painter: _AniListPainter(),
    );

    if (!withBackground) return logo;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1622),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(
          color: const Color(0xFF02A9FF).withOpacity(0.35),
          width: 1,
        ),
      ),
      padding: EdgeInsets.all(size * 0.16),
      child: logo,
    );
  }
}

class _AniListPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    // Path 1: Letter 'A'
    final pathA = Path();
    pathA.moveTo(11.034, 2.947);
    pathA.lineTo(17.371, 21.051);
    pathA.lineTo(12.453, 21.051);
    pathA.lineTo(11.401, 17.92);
    pathA.lineTo(6.019, 17.92);
    pathA.lineTo(4.942, 21.051);
    pathA.lineTo(0.0, 21.051);
    pathA.lineTo(6.361, 2.948);
    pathA.close();

    // Inner triangle of 'A'
    final innerA = Path();
    innerA.moveTo(10.374, 13.907);
    innerA.lineTo(8.684, 8.893);
    innerA.lineTo(7.143, 13.908);
    innerA.close();

    final paintA = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      Path.combine(PathOperation.difference, pathA, innerA),
      paintA,
    );

    // Path 2: AniList Cyan Bar/Arrow (#02A9FF)
    final pathL = Path();
    pathL.moveTo(24.0, 17.53);
    pathL.lineTo(24.0, 19.951);
    pathL.cubicTo(24.0, 20.661, 23.609, 21.052, 22.9, 21.052);
    pathL.lineTo(17.9, 21.052);
    pathL.lineTo(17.843, 20.887);
    pathL.lineTo(11.84, 3.736);
    pathL.cubicTo(11.946, 3.234, 12.3, 2.948, 12.893, 2.948);
    pathL.lineTo(15.315, 2.948);
    pathL.cubicTo(16.025, 2.948, 16.415, 3.339, 16.415, 4.048);
    pathL.lineTo(16.415, 16.428);
    pathL.lineTo(22.9, 16.428);
    pathL.cubicTo(23.61, 16.428, 24.0, 16.82, 24.0, 17.53);
    pathL.close();

    final paintL = Paint()
      ..color = const Color(0xFF02A9FF)
      ..style = PaintingStyle.fill;

    canvas.drawPath(pathL, paintL);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official MyAnimeList (MAL) logo widget drawn with crisp vector geometry.
class MalLogo extends StatelessWidget {
  final double size;
  final bool withBackground;

  const MalLogo({
    super.key,
    this.size = 36,
    this.withBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final logo = CustomPaint(
      size: Size(size, size),
      painter: _MalPainter(),
    );

    if (!withBackground) return logo;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2E51A2),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      padding: EdgeInsets.all(size * 0.16),
      child: logo,
    );
  }
}

class _MalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final path = Path();

    // 'M' section
    path.moveTo(0.0, 6.528);
    path.lineTo(0.0, 16.152);
    path.lineTo(2.348, 16.152);
    path.lineTo(2.348, 10.312);
    path.lineTo(4.379, 12.976);
    path.lineTo(6.426, 10.324);
    path.lineTo(6.426, 16.152);
    path.lineTo(8.762, 16.152);
    path.lineTo(8.762, 6.528);
    path.lineTo(6.437, 6.528);
    path.lineTo(4.368, 9.474);
    path.lineTo(2.31, 6.528);
    path.close();

    // 'A' section
    path.moveTo(14.921, 6.479);
    path.cubicTo(14.101, 6.479, 11.238, 6.479, 9.974, 9.635);
    path.cubicTo(9.312, 11.287, 8.988, 14.447, 10.85, 17.521);
    path.lineTo(12.784, 16.111);
    path.cubicTo(12.017, 15.016, 11.7, 13.921, 11.701, 12.92);
    path.lineTo(14.598, 12.92);
    path.lineTo(14.62, 16.11);
    path.lineTo(17.224, 16.11);
    path.lineTo(17.224, 8.835);
    path.lineTo(14.643, 8.835);
    path.lineTo(14.643, 10.878);
    path.lineTo(12.183, 10.855);
    path.cubicTo(12.596, 8.447, 14.647, 8.447, 15.06, 8.519);
    path.lineTo(17.514, 8.519);
    path.lineTo(16.942, 6.479);
    path.close();

    // 'L' section
    path.moveTo(18.447, 6.55);
    path.lineTo(18.447, 16.133);
    path.lineTo(23.469, 16.133);
    path.lineTo(24.0, 14.09);
    path.lineTo(20.768, 14.09);
    path.lineTo(20.768, 6.55);
    path.close();

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
