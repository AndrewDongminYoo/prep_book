import 'package:flutter/material.dart';

final class ChampionshipWordWrapText extends StatelessWidget {
  const ChampionshipWordWrapText({required this.text, this.style, super.key});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final fontSize = effectiveStyle.fontSize ?? 14;
    return Semantics(
      excludeSemantics: true,
      label: text,
      child: Wrap(
        spacing: MediaQuery.textScalerOf(context).scale(fontSize) / 4,
        children: [
          for (final word in text.split(' ')) Text(word, style: style),
        ],
      ),
    );
  }
}
