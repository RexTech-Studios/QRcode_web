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
      whatsappNumber: fields[5] as String?,
      notificationEmail: fields[6] as String?,
      emailNotificationsEnabled: (fields[7] as bool?) ?? false,
      googleSheetsUrl: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ShopModel obj) {
    writer
      ..writeByte(9)
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
      ..writeByte(5)
      ..write(obj.whatsappNumber)
      ..writeByte(6)
      ..write(obj.notificationEmail)
      ..writeByte(7)
      ..write(obj.emailNotificationsEnabled)
      ..writeByte(8)
      ..write(obj.googleSheetsUrl);
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
