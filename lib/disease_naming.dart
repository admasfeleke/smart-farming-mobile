String normalizeDiseaseKey(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'pending_analysis';
  }

  var normalized = trimmed.toLowerCase();
  normalized = normalized.replaceAll(RegExp(r'[\s\-/()]+'), '_');
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
  normalized = normalized.replaceAll(RegExp(r'_+'), '_');
  normalized = normalized.replaceAll(RegExp(r'^_|_$'), '');

  const pendingAliases = <String>{
    '',
    'pending_analysis',
    'analysis_pending',
    'pending',
    'processing',
    'queued',
    'submitted',
    'manual_review_required',
    'unknown',
    'unknown_issue',
    'healthy_or_unknown',
  };

  if (pendingAliases.contains(normalized)) {
    return 'pending_analysis';
  }

  if (normalized == 'maize_healthy' || normalized == 'corn_healthy') {
    return 'corn_healthy';
  }

  if (normalized.startsWith('maize_')) {
    normalized = 'corn_${normalized.substring('maize_'.length)}';
  }

  if (normalized.startsWith('corn_maize_')) {
    normalized = 'corn_${normalized.substring('corn_maize_'.length)}';
  }

  return normalized;
}

bool isPendingDiseaseKey(String? raw) => normalizeDiseaseKey(raw) == 'pending_analysis';

bool isHealthyDiseaseKey(String? raw) {
  final normalized = normalizeDiseaseKey(raw);
  return normalized == 'healthy' || normalized.endsWith('_healthy');
}

String? diseaseFamilyFromKey(String? raw) {
  final normalized = normalizeDiseaseKey(raw);
  if (normalized == 'pending_analysis') {
    return null;
  }
  final family = normalized.split('_').first;
  if (family.isEmpty) {
    return null;
  }
  return family == 'maize' ? 'corn' : family;
}

String localizedDiseaseLabel(String lang, String? raw) {
  final normalized = normalizeDiseaseKey(raw);
  if (normalized == 'pending_analysis') {
    return '';
  }

  const labels = <String, Map<String, String>>{
    'tomato_bacterial_spot': {
      'am': 'የቲማቲም ባክቴሪያ ቅጠል ነጠብጣብ',
      'om': 'Timaatima madoobbii baakteeriyaa',
      'ti': 'ናይ ቲማቲም ባክተርያ ነጥቢ ቅጠሊ',
      'en': 'Tomato Bacterial Spot',
    },
    'tomato_early_blight': {
      'am': 'የቲማቲም ቅጠል ዋግ',
      'om': 'Goginsa baala timaatimaa',
      'ti': 'ናይ ቲማቲም ቀዳማይ ምንቃጽ ቆጽሊ',
      'en': 'Tomato Early Blight',
    },
    'tomato_late_blight': {
      'am': 'የቲማቲም ዋግ',
      'om': 'Goginsa cimaa timaatimaa',
      'ti': 'ናይ ቲማቲም ደንጉዩ ምንቃጽ',
      'en': 'Tomato Late Blight',
    },
    'tomato_leaf_mold': {
      'am': 'የቲማቲም ቅጠል ሻጋታ',
      'om': 'Timaatima baqaqsaa baala',
      'ti': 'ናይ ቲማቲም ሻጋታ ቅጠሊ',
      'en': 'Tomato Leaf Mold',
    },
    'tomato_septoria_leaf_spot': {
      'am': 'የቲማቲም ሴፕቶሪያ ቅጠል ነጠብጣብ',
      'om': 'Timaatima septoria madoobbii baala',
      'ti': 'ናይ ቲማቲም ሴፕቶርያ ነጥቢ ቅጠሊ',
      'en': 'Tomato Septoria Leaf Spot',
    },
    'tomato_spider_mites_two_spotted_spider_mite': {
      'am': 'የቲማቲም ሁለት ነጥብ ሸረሪት ተባይ',
      'om': 'Timaatima bineensa xixiqqaa lama-tuqaa',
      'ti': 'ናይ ቲማቲም ክልተ ነጥቢ ሸረሪት ተባይ',
      'en': 'Tomato Two-Spotted Spider Mite',
    },
    'tomato_target_spot': {
      'am': 'የቲማቲም ዒላማ ነጠብጣብ',
      'om': 'Timaatima target spot',
      'ti': 'ናይ ቲማቲም ዒላማ ነጥቢ',
      'en': 'Tomato Target Spot',
    },
    'tomato_tomato_yellowleaf_curl_virus': {
      'am': 'የቲማቲም ቢጫ ቅጠል መጠቅለያ ቫይረስ',
      'om': 'Vaayirasii timaatima baala bifa keelloo marachuu',
      'ti': 'ቫይረስ ቲማቲም ቢጫ ቅጠሊ ጥቕላል',
      'en': 'Tomato Yellow Leaf Curl Virus',
    },
    'tomato_tomato_mosaic_virus': {
      'am': 'የቲማቲም ሞዛይክ ቫይረስ',
      'om': 'Vaayirasii mozaayikii timaatima',
      'ti': 'ቫይረስ ሞዛይክ ቲማቲም',
      'en': 'Tomato Mosaic Virus',
    },
    'tomato_healthy': {
      'am': 'ጤናማ ቲማቲም',
      'om': 'Timaatima fayyaa',
      'ti': 'ጥዑይ ቲማቲም',
      'en': 'Healthy Tomato',
    },
    'potato_early_blight': {
      'am': 'የድንች ቀዳሚ ቅጠል ዋግ',
      'om': 'Goginsa baala dinichaa',
      'ti': 'ናይ ድንሽ ቀዳማይ ምንቃጽ ቆጽሊ',
      'en': 'Potato Early Blight',
    },
    'potato_late_blight': {
      'am': 'የድንች ዋግ በሽታ',
      'om': 'Goginsa cimaa dinichaa',
      'ti': 'ናይ ድንሽ ደንጉዩ ምንቃጽ',
      'en': 'Potato Late Blight',
    },
    'potato_healthy': {
      'am': 'ጤናማ ድንች',
      'om': 'Dinicha fayyaa',
      'ti': 'ጥዑይ ድንሽ',
      'en': 'Healthy Potato',
    },
    'pepper_bell_bacterial_spot': {
      'am': 'የቃሪያ ባክቴሪያ ነጠብጣብ',
      'om': 'Qariya baakteeriyaa madoobbii',
      'ti': 'ናይ ቃርያ ባክተርያ ነጥቢ',
      'en': 'Pepper Bacterial Spot',
    },
    'pepper_bell_healthy': {
      'am': 'ጤናማ ቃሪያ',
      'om': 'Qariya fayyaa',
      'ti': 'ጥዑይ ቃርያ',
      'en': 'Healthy Pepper',
    },
    'corn_cercospora_leaf_spot_gray_leaf_spot': {
      'am': 'የበቆሎ ግራጫ ቅጠል ነጠብጣብ',
      'om': 'Madoobbii baala boqqolloo',
      'ti': 'ናይ በቆሎ ግራጫ ነጥቢ ቆጽሊ',
      'en': 'Maize Gray Leaf Spot',
    },
    'corn_common_rust': {
      'am': 'የበቆሎ የተለመደ ዝገት',
      'om': 'Daʼoo boqqolloo',
      'ti': 'ናይ በቆሎ ዝገት',
      'en': 'Maize Common Rust',
    },
    'corn_northern_leaf_blight': {
      'am': 'የበቆሎ ሰሜናዊ ቅጠል ዋግ',
      'om': 'Goginsa baala boqqolloo',
      'ti': 'ናይ በቆሎ ሰሜናዊ ምንቃጽ ቆጽሊ',
      'en': 'Maize Northern Leaf Blight',
    },
    'corn_healthy': {
      'am': 'ጤናማ በቆሎ',
      'om': 'Boqqolloo fayyaa',
      'ti': 'ጥዑይ በቆሎ',
      'en': 'Healthy Maize',
    },
  };

  final localized = labels[normalized]?[lang];
  if (localized != null && localized.isNotEmpty) {
    return localized;
  }
  final english = labels[normalized]?['en'];
  if (english != null && english.isNotEmpty) {
    return english;
  }
  return displayDiseaseLabel(raw);
}

String displayDiseaseLabel(String? raw) {
  final normalized = normalizeDiseaseKey(raw);
  if (normalized == 'pending_analysis') {
    return '';
  }

  final parts = normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(_displayWord)
      .toList(growable: false);
  return parts.join(' ');
}

String _displayWord(String word) {
  switch (word) {
    case 'ph':
      return 'pH';
    case 'ppi':
      return 'PPI';
    case 'rei':
      return 'REI';
    case 'curl':
      return 'Curl';
    case 'virus':
      return 'Virus';
    case 'leaf':
      return 'Leaf';
    case 'spot':
      return 'Spot';
    case 'blight':
      return 'Blight';
    default:
      if (word.length <= 2) {
        return word.toUpperCase();
      }
      return '${word[0].toUpperCase()}${word.substring(1)}';
  }
}
