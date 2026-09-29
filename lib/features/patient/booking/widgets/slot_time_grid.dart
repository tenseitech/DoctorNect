import 'package:flutter/material.dart';

import '../models/booking_models.dart';
import 'slot_time_button.dart';

/// Responsive slot grid: fixed column count with equal-width cells on every row.
class SlotTimeGrid extends StatelessWidget {
  const SlotTimeGrid({
    super.key,
    required this.slots,
    required this.selectedSlotId,
    required this.onSlot,
    this.columns = 3,
    this.spacing = 8,
  });

  final List<TimeSlot> slots;
  final String? selectedSlotId;
  final ValueChanged<TimeSlot> onSlot;
  final int columns;
  final double spacing;

  int _columnCount(double maxWidth) => columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _columnCount(constraints.maxWidth);
        final itemWidth =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;

        final rows = <Widget>[];
        for (var i = 0; i < slots.length; i += crossAxisCount) {
          if (rows.isNotEmpty) {
            rows.add(SizedBox(height: spacing));
          }

          final chunk = slots.sublist(
            i,
            i + crossAxisCount > slots.length
                ? slots.length
                : i + crossAxisCount,
          );

          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < crossAxisCount; j++) ...[
                  if (j > 0) SizedBox(width: spacing),
                  SizedBox(
                    width: itemWidth,
                    child: j < chunk.length
                        ? _SlotCell(
                            slot: chunk[j],
                            selected: selectedSlotId == chunk[j].id,
                            onSlot: onSlot,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

class _SlotCell extends StatelessWidget {
  const _SlotCell({
    required this.slot,
    required this.selected,
    required this.onSlot,
  });

  final TimeSlot slot;
  final bool selected;
  final ValueChanged<TimeSlot> onSlot;

  @override
  Widget build(BuildContext context) {
    final unavailable = !slot.isSelectable;
    return SlotTimeButton(
      label: slot.label,
      selected: selected,
      booked: unavailable,
      bookingCount: slot.bookingCount,
      compact: true,
      onTap: unavailable ? null : () => onSlot(slot),
    );
  }
}
