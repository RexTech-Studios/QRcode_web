// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ShopModelAdapter extends TypeAdapter<ShopModel> {
  @override
  final int typeId = 0;

  @override
  ShopModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ShopModel(
      shopId: fields[0] as String,
      shopName: fields[1] as String,
      shopLogo: fields[2] as String?,
      googleReviewUrl: fields[3] as String,
      createdAt: fields[4] as DateTime,
      googleSheetsUrl: fields[8] as String?,
      qrCode: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ShopModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.shopId)
      ..writeByte(1)
      ..write(obj.shopName)
      ..writeByte(2)
      ..write(obj.shopLogo)
      ..writeByte(3)
      ..write(obj.googleReviewUrl)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.googleSheetsUrl)
      ..writeByte(9)
      ..write(obj.qrCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShopModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
