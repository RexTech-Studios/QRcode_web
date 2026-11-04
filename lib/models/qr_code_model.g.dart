// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'qr_code_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class QRCodeModelAdapter extends TypeAdapter<QRCodeModel> {
  @override
  final int typeId = 2;

  @override
  QRCodeModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QRCodeModel(
      qrId: fields[0] as String,
      shopId: fields[1] as String,
      qrContent: fields[2] as String,
      qrLabel: fields[3] as String,
      qrStyle: fields[4] as QRStyle,
      createdAt: fields[5] as DateTime,
      updatedAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, QRCodeModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.qrId)
      ..writeByte(1)
      ..write(obj.shopId)
      ..writeByte(2)
      ..write(obj.qrContent)
      ..writeByte(3)
      ..write(obj.qrLabel)
      ..writeByte(4)
      ..write(obj.qrStyle)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QRCodeModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class QRStyleAdapter extends TypeAdapter<QRStyle> {
  @override
  final int typeId = 1;

  @override
  QRStyle read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return QRStyle.classic;
      case 1:
        return QRStyle.rounded;
      case 2:
        return QRStyle.dotsGreen;
      case 3:
        return QRStyle.minimal;
      default:
        return QRStyle.classic;
    }
  }

  @override
  void write(BinaryWriter writer, QRStyle obj) {
    switch (obj) {
      case QRStyle.classic:
        writer.writeByte(0);
        break;
      case QRStyle.rounded:
        writer.writeByte(1);
        break;
      case QRStyle.dotsGreen:
        writer.writeByte(2);
        break;
      case QRStyle.minimal:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QRStyleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
