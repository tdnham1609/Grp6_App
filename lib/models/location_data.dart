/// Dữ liệu vị trí GPS gần nhất của người dùng
/// Chỉ lưu trữ cục bộ (SQLite) cho đến khi có điều kiện kích hoạt hợp lệ
class LocationData {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.timestamp,
  });

  /// Kiểm tra dữ liệu vị trí có mới hơn vị trí khác không
  /// Dùng để đảm bảo không ghi đè dữ liệu mới bằng dữ liệu cũ hơn
  bool isNewerThan(LocationData other) {
    return timestamp.isAfter(other.timestamp);
  }

  /// Kiểm tra toạ độ có hợp lệ về mặt địa lý không
  bool get isValid {
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  /// Chuỗi hiển thị thân thiện cho thời điểm lấy vị trí
  /// Luôn hiển thị timestamp để người dùng biết rõ đây là vị trí cũ hay mới
  String get timestampFormatted {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Vừa cập nhật';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
  }

  /// Chuỗi hiển thị độ chính xác GPS
  String get accuracyFormatted {
    if (accuracy == null) return 'Không rõ';
    if (accuracy! < 10) return 'Rất cao (~${accuracy!.toStringAsFixed(0)}m)';
    if (accuracy! < 50) return 'Cao (~${accuracy!.toStringAsFixed(0)}m)';
    if (accuracy! < 100) return 'Trung bình (~${accuracy!.toStringAsFixed(0)}m)';
    return 'Thấp (~${accuracy!.toStringAsFixed(0)}m)';
  }

  /// Chuyển thành Map để lưu vào SQLite
  Map<String, dynamic> toSqlite() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'location_timestamp': timestamp.toIso8601String(),
    };
  }

  /// Tạo LocationData từ SQLite row
  /// Trả về null nếu không có dữ liệu vị trí
  static LocationData? fromSqlite(Map<String, dynamic> row) {
    final lat = row['latitude'] as num?;
    final lng = row['longitude'] as num?;
    final ts = row['location_timestamp'] as String?;

    if (lat == null || lng == null || ts == null) return null;

    final parsedTime = DateTime.tryParse(ts);
    if (parsedTime == null) return null;

    return LocationData(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      accuracy: (row['accuracy'] as num?)?.toDouble(),
      timestamp: parsedTime,
    );
  }

  @override
  String toString() {
    // Không hiển thị toạ độ chính xác trong log để bảo vệ quyền riêng tư
    return 'LocationData(timestamp: $timestamp, accuracy: ${accuracy?.toStringAsFixed(1)}m)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationData &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(latitude, longitude, timestamp);
}
