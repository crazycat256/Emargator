class TimeSlot {
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  const TimeSlot({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  DateTime getStartTime(DateTime date) {
    return DateTime(date.year, date.month, date.day, startHour, startMinute);
  }

  DateTime getEndTime(DateTime date) {
    return DateTime(date.year, date.month, date.day, endHour, endMinute);
  }

  bool contains(DateTime time) {
    final start = getStartTime(time);
    final end = getEndTime(time);
    return time.isAfter(start) && time.isBefore(end) ||
        time.isAtSameMomentAs(start) ||
        time.isAtSameMomentAs(end);
  }

  String getTimeRange() {
    return '${_formatTime(startHour, startMinute)} - ${_formatTime(endHour, endMinute)}';
  }

  String _formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class TimeSlotInfo {
  final bool isInSlot;
  final TimeSlot? currentSlot;
  final TimeSlot? nextSlot;
  final Duration? timeUntilNextSlot;

  const TimeSlotInfo({
    required this.isInSlot,
    this.currentSlot,
    this.nextSlot,
    this.timeUntilNextSlot,
  });
}

class TimeSlotService {
  static const List<TimeSlot> _slots = [
    TimeSlot(startHour: 8, startMinute: 0, endHour: 9, endMinute: 30),
    TimeSlot(startHour: 9, startMinute: 45, endHour: 11, endMinute: 15),
    TimeSlot(startHour: 11, startMinute: 30, endHour: 13, endMinute: 0),
    TimeSlot(startHour: 13, startMinute: 0, endHour: 14, endMinute: 30),
    TimeSlot(startHour: 14, startMinute: 45, endHour: 16, endMinute: 15),
    TimeSlot(startHour: 16, startMinute: 30, endHour: 18, endMinute: 0),
    TimeSlot(startHour: 18, startMinute: 15, endHour: 19, endMinute: 45),
  ];

  static TimeSlotInfo getCurrentSlotInfo([DateTime? now]) {
    now ??= DateTime.now();

    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return const TimeSlotInfo(isInSlot: false);
    }

    for (final slot in _slots) {
      if (slot.contains(now)) {
        return TimeSlotInfo(isInSlot: true, currentSlot: slot);
      }
    }

    TimeSlot? nextSlot;
    Duration? timeUntilNext;

    for (final slot in _slots) {
      final startTime = slot.getStartTime(now);
      if (now.isBefore(startTime)) {
        nextSlot = slot;
        timeUntilNext = startTime.difference(now);
        break;
      }
    }

    if (nextSlot == null) {
      DateTime nextDay = now.add(const Duration(days: 1));
      while (nextDay.weekday == DateTime.saturday ||
          nextDay.weekday == DateTime.sunday) {
        nextDay = nextDay.add(const Duration(days: 1));
      }
      nextSlot = _slots.first;
      timeUntilNext = nextSlot.getStartTime(nextDay).difference(now);
    }

    return TimeSlotInfo(
      isInSlot: false,
      nextSlot: nextSlot,
      timeUntilNextSlot: timeUntilNext,
    );
  }

  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 24) {
      final days = hours ~/ 24;
      final remainingHours = hours.remainder(24);
      if (remainingHours == 0) {
        return '$days jour${days > 1 ? 's' : ''}';
      }
      return '$days jour${days > 1 ? 's' : ''} et $remainingHours h';
    } else if (hours > 0) {
      if (minutes == 0) {
        return '$hours h';
      }
      return '$hours h ${minutes.toString().padLeft(2, '0')} min';
    } else {
      return '$minutes min';
    }
  }
}
