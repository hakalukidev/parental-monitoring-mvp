import 'dart:convert';
import 'package:flutter/material.dart';
import 'seftly_theme.dart';

class SeftlyMark extends StatelessWidget {
  final double size;
  const SeftlyMark({super.key, this.size = 56});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Seftly family safety',
        image: true,
        child: Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * .18),
          decoration: BoxDecoration(
              color: context.colors.primary,
              borderRadius: BorderRadius.circular(size * .3)),
          child: CustomPaint(painter: _ShieldPainter(context.colors.onPrimary)),
        ),
      );
}

class _ShieldPainter extends CustomPainter {
  final Color color;
  _ShieldPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width * .5, 0)
      ..lineTo(size.width * .94, size.height * .17)
      ..lineTo(size.width * .88, size.height * .58)
      ..quadraticBezierTo(
          size.width * .8, size.height * .84, size.width * .5, size.height)
      ..quadraticBezierTo(size.width * .2, size.height * .84, size.width * .12,
          size.height * .58)
      ..lineTo(size.width * .06, size.height * .17)
      ..close();
    canvas.drawPath(
        p,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .07
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(Offset(size.width * .5, size.height * .35),
        size.width * .11, Paint()..color = color);
    canvas.drawPath(
        Path()
          ..moveTo(size.width * .28, size.height * .66)
          ..quadraticBezierTo(size.width * .5, size.height * .43,
              size.width * .72, size.height * .66),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .08
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_ShieldPainter oldDelegate) => oldDelegate.color != color;
}

class PageIntro extends StatelessWidget {
  final String title, subtitle;
  final IconData? icon;
  const PageIntro(
      {super.key, required this.title, required this.subtitle, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            SeftlyTokens.gutter, 20, SeftlyTokens.gutter, 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: context.colors.onPrimaryContainer)),
            const SizedBox(width: 14)
          ],
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 5),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: context.muted))
              ])),
        ]),
      );
}

/// Maintains the existing screen actions and bounded bodies (including maps/tabs).
/// The intro collapses on short/large-text viewports to keep controls reachable.
class SeftlyScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body, floatingActionButton, bottomNavigationBar;
  final Color? backgroundColor;
  final String title, subtitle;
  final IconData icon;
  const SeftlyScaffold(
      {super.key,
      this.appBar,
      this.body,
      this.floatingActionButton,
      this.bottomNavigationBar,
      this.backgroundColor,
      required this.title,
      required this.subtitle,
      required this.icon});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: backgroundColor,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: SafeArea(
            top: false,
            child: LayoutBuilder(
                builder: (context, box) => Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: SeftlyTokens.contentWidth),
                        child: Column(children: [
                          if (box.maxHeight > 520 &&
                              MediaQuery.textScalerOf(context).scale(1) < 1.6)
                            PageIntro(
                                title: title, subtitle: subtitle, icon: icon),
                          if (body != null) Expanded(child: body!),
                        ]))))),
      );
}

class SeftlyStateView extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool error;
  const SeftlyStateView(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.actionLabel,
      this.onAction,
      this.error = false});
  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: error
                            ? context.colors.errorContainer
                            : context.colors.primaryContainer,
                        shape: BoxShape.circle),
                    child: Icon(icon,
                        size: 32,
                        color: error
                            ? context.colors.onErrorContainer
                            : context.colors.onPrimaryContainer)),
                const SizedBox(height: 20),
                Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.muted)),
                if (onAction != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel ?? 'Try again'))
                ],
              ]))));
}

class StatusPill extends StatelessWidget {
  final String label;
  final bool active;
  const StatusPill({super.key, required this.label, this.active = false});
  @override
  Widget build(BuildContext context) => Semantics(
      label: label,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              color: active
                  ? context.colors.primaryContainer
                  : context.colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(30)),
          child: Text(label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: active
                      ? context.colors.onPrimaryContainer
                      : context.colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600))));
}

class AuthFrame extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final Widget form;
  const AuthFrame(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.form,
      this.eyebrow = 'SEFTLY · FAMILY SAFETY'});
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: LayoutBuilder(
              builder: (context, size) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight:
                              (size.maxHeight - 48).clamp(0, double.infinity)),
                      child: Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 460),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SeftlyMark(size: 64),
                                    const SizedBox(height: 28),
                                    Text(eyebrow,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                                color: context.colors.primary,
                                                letterSpacing: 1.5)),
                                    const SizedBox(height: 12),
                                    Text(title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineLarge),
                                    const SizedBox(height: 12),
                                    Text(subtitle,
                                        style: TextStyle(
                                            color: context.muted, height: 1.5)),
                                    const SizedBox(height: 28),
                                    Card(
                                        child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: form)),
                                    const SizedBox(height: 24),
                                    Text(
                                        'A little guidance. More peace of mind.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: context.muted)),
                                  ]))))))));
}

class AppThumbnail extends StatelessWidget {
  final String? encoded;
  final IconData fallback;
  final Color? color;
  const AppThumbnail(
      {super.key, this.encoded, required this.fallback, this.color});
  @override
  Widget build(BuildContext context) {
    final icon = Icon(fallback, color: color ?? context.colors.primary);
    if (encoded == null) return icon;
    try {
      return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(base64Decode(encoded!),
              width: 36,
              height: 36,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => icon,
              excludeFromSemantics: true));
    } catch (_) {
      return icon;
    }
  }
}

class FamilyLoadingView extends StatelessWidget {
  const FamilyLoadingView({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Loading your family',
      liveRegion: true,
      child: ExcludeSemantics(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        for (var i = 0; i < 3; i++)
          Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                width: 150,
                                height: 20,
                                decoration: BoxDecoration(
                                    color:
                                        context.colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8))),
                            const SizedBox(height: 16),
                            Container(
                                height: 70,
                                decoration: BoxDecoration(
                                    color: context.colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(14))),
                          ])))),
      ])));
}
