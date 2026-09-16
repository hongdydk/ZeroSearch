import 'package:flutter/material.dart';

/// 담기 전 수량. [min] 이상 [max] 이하.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 1,
    this.enabled = true,
  });

  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final canDec = enabled && value > min;
    final canInc = enabled && value < max;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '수량 줄이기',
          icon: const Icon(Icons.remove),
          onPressed: canDec ? () => onChanged(value - 1) : null,
        ),
        Text('$value', style: Theme.of(context).textTheme.titleSmall),
        IconButton(
          tooltip: '수량 늘리기',
          icon: const Icon(Icons.add),
          onPressed: canInc ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
