const Set<String> kDefaultSupportedCropFamilies = <String>{
  'pepper',
  'potato',
  'tomato',
};

Set<String> _supportedCropFamilies = Set<String>.from(kDefaultSupportedCropFamilies);

Set<String> get kSupportedCropFamilies => Set<String>.unmodifiable(_supportedCropFamilies);

void updateSupportedCropFamilies(Iterable<String> families) {
  final normalized = families
      .map((family) => family.trim().toLowerCase())
      .where((family) => family.isNotEmpty)
      .toSet();
  _supportedCropFamilies = normalized.isEmpty
      ? Set<String>.from(kDefaultSupportedCropFamilies)
      : normalized;
}

String? cropFamilyFromName(String? cropName) {
  if (cropName == null) return null;
  final trimmed = cropName.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  final slug = trimmed.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  final normalized = slug.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  if (normalized.isEmpty) return null;
  final family = normalized.split('_').first;
  if (family == 'maize') return 'corn';
  return family;
}

bool isSupportedCropName(String? cropName) {
  final family = cropFamilyFromName(cropName);
  if (family == null) return false;
  return kSupportedCropFamilies.contains(family);
}

List<Map<String, dynamic>> filterSupportedCropEntries(List<Map<String, dynamic>> crops) {
  return crops.where((c) => isSupportedCropName(c['name']?.toString())).toList();
}

Set<int> supportedCropIds(List<Map<String, dynamic>> crops) {
  final ids = <int>{};
  for (final c in crops) {
    if (!isSupportedCropName(c['name']?.toString())) continue;
    final idValue = c['id'];
    if (idValue is int) {
      ids.add(idValue);
      continue;
    }
    if (idValue is num) {
      ids.add(idValue.toInt());
      continue;
    }
    if (idValue != null) {
      final parsed = int.tryParse(idValue.toString());
      if (parsed != null) ids.add(parsed);
    }
  }
  return ids;
}
