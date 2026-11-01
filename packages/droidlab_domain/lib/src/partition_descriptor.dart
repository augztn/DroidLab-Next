/// Partition metadata discovered from the active Fastboot transport.
final class PartitionDescriptor {
  const PartitionDescriptor({
    required this.name,
    this.size,
    this.type,
    this.hasSlot,
    this.isLogical,
  });

  final String name;
  final String? size;
  final String? type;
  final bool? hasSlot;
  final bool? isLogical;

  factory PartitionDescriptor.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Partition name must be a non-empty string.');
    }
    return PartitionDescriptor(
      name: name,
      size: _optionalString(json['size']),
      type: _optionalString(json['type']),
      hasSlot: _optionalBool(json['has_slot']),
      isLogical: _optionalBool(json['is_logical']),
    );
  }
}

String? _optionalString(Object? value) => value is String ? value : null;
bool? _optionalBool(Object? value) => switch (value) {
  true => true,
  false => false,
  'yes' => true,
  'no' => false,
  _ => null,
};
