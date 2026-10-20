import 'package:flutter/material.dart';

/// A wrapping row of compact controls shown above the scenario.
class ControlsRow extends StatelessWidget {
  const ControlsRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

/// An on/off toggle drawn as a filter chip.
class ToggleChip extends StatelessWidget {
  const ToggleChip({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A labelled single-choice segmented control.
class SegmentChoice<T> extends StatelessWidget {
  const SegmentChoice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;

  /// Option value to its button text.
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    // Scales down rather than overflowing on a narrow phone.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(width: 6),
          SegmentedButton<T>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: <ButtonSegment<T>>[
              for (final MapEntry<T, String> e in options.entries)
                ButtonSegment<T>(value: e.key, label: Text(e.value)),
            ],
            selected: <T>{value},
            onSelectionChanged: (Set<T> s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}

/// A labelled slider with its current value printed at the end.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.unit = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Row(
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          Text(
            '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)}$unit',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

/// A small tonal button for one-shot actions.
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
