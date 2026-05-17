// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_dto.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GoalDtoAdapter extends TypeAdapter<GoalDto> {
  @override
  final int typeId = 0;

  @override
  GoalDto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GoalDto()
      ..goalId = fields[0] as String
      ..title = fields[1] as String
      ..notes = fields[2] as String
      ..status = fields[3] as String
      ..dueDate = fields[4] as DateTime?
      ..subtasks = (fields[5] as List).cast<SubTaskDto>()
      ..isFocusedToday = fields[6] as bool
      ..todayOrder = fields[7] as int
      ..difficulty = fields[8] as String?
      ..emoji = fields[9] as String?;
  }

  @override
  void write(BinaryWriter writer, GoalDto obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.goalId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.notes)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.dueDate)
      ..writeByte(5)
      ..write(obj.subtasks)
      ..writeByte(6)
      ..write(obj.isFocusedToday)
      ..writeByte(7)
      ..write(obj.todayOrder)
      ..writeByte(8)
      ..write(obj.difficulty)
      ..writeByte(9)
      ..write(obj.emoji);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalDtoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
