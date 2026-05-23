// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sub_task_dto.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SubTaskDtoAdapter extends TypeAdapter<SubTaskDto> {
  @override
  final int typeId = 1;

  @override
  SubTaskDto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SubTaskDto()
      ..subtaskId = fields[0] as String
      ..description = fields[1] as String
      ..state = fields[2] as String
      ..assignedDate = fields[3] as DateTime
      ..completionDate = fields[4] as DateTime?
      ..lastSeenDate = fields[5] as DateTime
      ..effortEstimate = fields[6] as int?
      ..snoozedUntil = fields[7] as DateTime?
      ..notifyOnWake = fields[8] as bool?
      ..autoSleepSeconds = fields[9] as int?
      ..estimatedMinutes = fields[10] as int?;
  }

  @override
  void write(BinaryWriter writer, SubTaskDto obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.subtaskId)
      ..writeByte(1)
      ..write(obj.description)
      ..writeByte(2)
      ..write(obj.state)
      ..writeByte(3)
      ..write(obj.assignedDate)
      ..writeByte(4)
      ..write(obj.completionDate)
      ..writeByte(5)
      ..write(obj.lastSeenDate)
      ..writeByte(6)
      ..write(obj.effortEstimate)
      ..writeByte(7)
      ..write(obj.snoozedUntil)
      ..writeByte(8)
      ..write(obj.notifyOnWake)
      ..writeByte(9)
      ..write(obj.autoSleepSeconds)
      ..writeByte(10)
      ..write(obj.estimatedMinutes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubTaskDtoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
