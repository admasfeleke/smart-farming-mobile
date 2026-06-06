import 'language_config.dart';

class LocalizedValue {
  static const Map<String, Map<String, String>> _status = {
    'am': {
      'open': 'ክፍት',
      'acknowledged': 'ተቀብሏል',
      'resolved': 'ተፈትቷል',
      'confirmed': 'ተረጋግጧል',
      'verified': 'ተረጋግጧል',
      'rejected': 'ተከልክሏል',
      'reviewing': 'በግምገማ ላይ',
      'planned': 'ታቅዷል',
      'active': 'ንቁ',
      'harvested': 'ተሰብስቧል',
      'failed': 'አልተሳካም',
      'good': 'ጥሩ',
      'pending': 'በመጠባበቅ ላይ',
      'pending_analysis': 'በመጠባበቅ ላይ',
      'analysis_pending': 'በመጠባበቅ ላይ',
      'processing': 'በመስራት ላይ',
      'queued': 'በተራ ላይ',
      'submitted': 'ቀርቧል',
      'new': 'አዲስ',
      'monitor_only': 'ክትትል ብቻ',
      'completed': 'ተጠናቋል',
    },
    'om': {
      'open': 'Banaa',
      'acknowledged': 'Fudhatame',
      'resolved': 'Furame',
      'confirmed': 'Mirkanaa’e',
      'verified': 'Mirkanaa’e',
      'rejected': 'Kufsiifame',
      'reviewing': 'Gamaaggamaa jira',
      'planned': 'Karoorfame',
      'active': 'Hojii irra',
      'harvested': 'Haammatame',
      'failed': 'Hin milkoofne',
      'good': 'Gaarii',
      'pending': 'Eeggamaa jira',
      'pending_analysis': 'Eeggamaa jira',
      'analysis_pending': 'Eeggamaa jira',
      'processing': 'Adeemsarra jira',
      'queued': 'Tartarree irra jira',
      'submitted': 'Dhiyaateera',
      'new': 'Haaraa',
      'monitor_only': 'To’annoo qofa',
      'completed': 'Xumurame',
    },
    'ti': {
      'open': 'ክፉት',
      'acknowledged': 'ተቐቢሉ',
      'resolved': 'ተፈቲሑ',
      'confirmed': 'ተረጋጊጹ',
      'verified': 'ተረጋጊጹ',
      'rejected': 'ተኸልኪሉ',
      'reviewing': 'ኣብ ግምገማ ኣሎ',
      'planned': 'ዝተመደበ',
      'active': 'ንቁሕ',
      'harvested': 'ዝተኣከበ',
      'failed': 'ዘይተሳኸዐ',
      'good': 'ጽቡቕ',
      'pending': 'ይጽበ',
      'pending_analysis': 'ይጽበ',
      'analysis_pending': 'ይጽበ',
      'processing': 'ኣብ ስራሕ ኣሎ',
      'queued': 'ኣብ ተራ ኣሎ',
      'submitted': 'ቀሪቡ',
      'new': 'ሓድሽ',
      'monitor_only': 'ክትትል ጥራይ',
      'completed': 'ተዛዚሙ',
    },
    'en': {
      'open': 'Open',
      'acknowledged': 'Acknowledged',
      'resolved': 'Resolved',
      'confirmed': 'Confirmed',
      'verified': 'Verified',
      'rejected': 'Rejected',
      'reviewing': 'Reviewing',
      'planned': 'Planned',
      'active': 'Active',
      'harvested': 'Harvested',
      'failed': 'Failed',
      'good': 'Good',
      'pending': 'Pending',
      'pending_analysis': 'Pending',
      'analysis_pending': 'Pending',
      'processing': 'Pending',
      'queued': 'Pending',
      'submitted': 'Pending',
      'new': 'New',
      'monitor_only': 'Monitor only',
      'completed': 'Completed',
    },
  };

  static const Map<String, Map<String, String>> _fixed = {
    'am': {
      'not_available': 'አይገኝም',
      'unknown': 'ያልታወቀ',
      'soil_label': 'አፈር',
      'flash_panel': 'ፍላሽ',
      'flashlight': 'መብራት',
      'flashlight_unavailable': 'የፍላሽ መብራት በዚህ መሣሪያ ላይ አይገኝም።',
      'flash_on': 'በርቷል',
      'flash_off': 'ጠፍቷል',
      'zoom_in': 'አቅርብ',
      'zoom_out': 'አርቅ',
      'upload_last_image': 'የመጨረሻ ምስል ጫን',
      'scan_result_rejected': 'ተከልክሏል',
      'scan_result_pending_review': 'ግምገማ በመጠባበቅ ላይ',
      'scan_result_diagnosis_confirmed': 'ምርመራው ተረጋግጧል',
      'scan_result_needs_verification': 'ማረጋገጫ ያስፈልጋል',
      'scan_result_treatment_ready': 'የሕክምና መመሪያ ዝግጁ ነው',
      'crop_mismatch_treatment_blocked':
          'ለዚህ ሪፖርት ሕክምና ተዘግቷል። ትክክለኛውን ሰብል መርጠው እንደገና ይስኩ።',
      'yield_prediction_short': 'የምርት ትንበያ',
      'scan_no_captured_image': 'ለመጫን የተቀረጸ ምስል የለም። መጀመሪያ ፎቶ ያንሱ።',
      'scan_last_image_unavailable': 'የመጨረሻው ምስል አይገኝም። እንደገና ያንሱ።',
      'scan_auto_paused_low_quality': 'አውቶ ስካን ዝቅተኛ ጥራት ምክንያት ተዘግቷል።',
      'recent_rain_last_7_days': 'የቅርብ ዝናብ (ያለፉት 7 ቀናት)',
      'no_matching_items_found': 'ተመሳሳይ ንጥል አልተገኘም።',
      'no_prediction_available_yet': 'እስካሁን የምርት ትንበያ የለም',
      'yield_prediction_empty_help': 'ከላይ ያለውን ቁልፍ ተጠቅመው ለዚህ ተክል አዲስ የምርት ግምት ያዘጋጁ።',
      'temperature_celsius_short': 'ሙቀት (°C)',
      'crop_short': 'ሰብል',
      'plot_short': 'ማሳ',
      'reports_count': '{count} ሪፖርቶች',
      'optional_field_context': 'አማራጭ የማሳ አውድ',
    },
    'om': {
      'not_available': 'Hin argamne',
      'unknown': 'Hin beekamne',
      'soil_label': 'Biyyoo',
      'flash_panel': 'Faalaashii',
      'flashlight': 'Ifa faalaashii',
      'flashlight_unavailable': 'Ifni faalaashii meeshaa kana irratti hin jiru.',
      'flash_on': 'Banaa',
      'flash_off': 'Cufaa',
      'zoom_in': 'Guddisi',
      'zoom_out': 'Xiqqeessi',
      'upload_last_image': 'Suuraa dhumaa olkaa’i',
      'scan_result_rejected': 'Kufsiifame',
      'scan_result_pending_review': 'Eeggii gamaaggamaa',
      'scan_result_diagnosis_confirmed': 'Bu’aan mirkanaa’e',
      'scan_result_needs_verification': 'Mirkaneessi barbaachisa',
      'scan_result_treatment_ready': 'Qajeelfamni yaalaa qophaa’eera',
      'crop_mismatch_treatment_blocked':
          'Qajeelfamni yaalaa gabaasa kanaaf cufameera. Midhaan sirrii filadhuu irra deebi’ii skaan godhi.',
      'yield_prediction_short': 'Raaga omishaa',
      'scan_no_captured_image': 'Suuraan kaafame olkaa’amu hin jiru. Jalqaba suuraa kaasi.',
      'scan_last_image_unavailable': 'Suuraan dhumaa hin argamne. Irra deebi’ii kaasi.',
      'scan_auto_paused_low_quality': 'Skaaniin ofumaan sababa qulqullina gadi aanaa irraa dhaabbateera.',
      'recent_rain_last_7_days': 'Rooba dhihoo (guyyoota 7 darban)',
      'no_matching_items_found': 'Wanti wal fakkaatu hin argamne.',
      'no_prediction_available_yet': 'Raagni omishaa ammatti hin jiru',
      'yield_prediction_empty_help':
          'Qabduu ol jiru fayyadamuun dhaabbata kanaaf raaga omishaa haaraa baasi.',
      'temperature_celsius_short': 'Ho’a (°C)',
      'crop_short': 'Midhaan',
      'plot_short': 'Lafa qonnaa',
      'reports_count': 'Gabaasota {count}',
      'optional_field_context': 'Haala dirree filannoo',
    },
    'ti': {
      'not_available': 'የለን',
      'unknown': 'ዘይተፈልጠ',
      'soil_label': 'መሬት',
      'flash_panel': 'ፍላሽ',
      'flashlight': 'መብራህቲ',
      'flashlight_unavailable': 'ፍላሽ መብራህቲ ኣብዚ መሳርሒ የለን።',
      'flash_on': 'በሪሁ',
      'flash_off': 'ጠፊኡ',
      'zoom_in': 'ኣቕርብ',
      'zoom_out': 'ኣርሕቕ',
      'upload_last_image': 'ናይ መወዳእታ ምስሊ ጸዓን',
      'scan_result_rejected': 'ተኸልኪሉ',
      'scan_result_pending_review': 'ግምገማ ይጽበ',
      'scan_result_diagnosis_confirmed': 'ምርመራ ተረጋጊጹ',
      'scan_result_needs_verification': 'ምርግጋጽ የድሊ',
      'scan_result_treatment_ready': 'መምርሒ ሕክምና ድሉው እዩ',
      'crop_mismatch_treatment_blocked':
          'እዚ ሪፖርት ሕክምና ተዓጽዩ ኣሎ። ትኽክለኛውን ሰብል መሪጽካ እንደገና ስካን ግበር።',
      'yield_prediction_short': 'ትንበያ ፍርያት',
      'scan_no_captured_image': 'ዝተቐርጸ ምስሊ ንምጽዓን የለን። ቅድሚ ኩሉ ስእሊ ኣልዕል።',
      'scan_last_image_unavailable': 'ናይ መወዳእታ ምስሊ የለን። እንደገና ኣልዕል።',
      'scan_auto_paused_low_quality': 'ኣውቶ ስካን ብዝተናኸሰ ጥራይ ጥራት ተዓጽዩ።',
      'recent_rain_last_7_days': 'ናይ ቀረባ ዝናብ (ዝሓለፉ 7 መዓልታት)',
      'no_matching_items_found': 'ዝሰማማዕ ንጥል ኣይተረኽበን።',
      'no_prediction_available_yet': 'ክሳብ ሕጂ ትንበያ ፍርያት የለን',
      'yield_prediction_empty_help':
          'ነዚ ተኽሊ ሓድሽ ግምት ፍርያት ንምፍጣር ኣብ ላዕሊ ዘሎ መርገጺ ተጠቐም።',
      'temperature_celsius_short': 'ሙቐት (°C)',
      'crop_short': 'ሰብል',
      'plot_short': 'ማሳ',
      'reports_count': '{count} ሪፖርታት',
      'optional_field_context': 'ኣማራጺ ኩነታት ማሳ',
    },
    'en': {
      'not_available': 'Not available',
      'unknown': 'Unknown',
      'soil_label': 'Soil',
      'flash_panel': 'Flash',
      'flashlight': 'Flashlight',
      'flashlight_unavailable': 'Flashlight not available on this device.',
      'flash_on': 'ON',
      'flash_off': 'OFF',
      'zoom_in': 'Zoom in',
      'zoom_out': 'Zoom out',
      'upload_last_image': 'Upload last image',
      'scan_result_rejected': 'Rejected',
      'scan_result_pending_review': 'Pending review',
      'scan_result_diagnosis_confirmed': 'Diagnosis confirmed',
      'scan_result_needs_verification': 'Needs verification',
      'scan_result_treatment_ready': 'Treatment ready',
      'crop_mismatch_treatment_blocked':
          'Treatment is blocked for this report. Rescan after selecting the correct crop.',
      'yield_prediction_short': 'Yield prediction',
      'scan_no_captured_image': 'No captured image to upload. Take a photo first.',
      'scan_last_image_unavailable': 'Last image is unavailable. Capture again.',
      'scan_auto_paused_low_quality': 'Auto scan paused after low-quality capture.',
      'recent_rain_last_7_days': 'Recent rain (last 7 days)',
      'no_matching_items_found': 'No matching items found.',
      'no_prediction_available_yet': 'No prediction available yet',
      'yield_prediction_empty_help':
          'Use the button above to generate a fresh yield estimate for this planting.',
      'temperature_celsius_short': 'Temperature (°C)',
      'crop_short': 'Crop',
      'plot_short': 'Plot',
      'reports_count': '{count} reports',
      'optional_field_context': 'Optional field context',
    },
  };

  static const Map<String, Map<String, String>> _crops = {
    'am': {
      'tomato': 'ቲማቲም',
      'potato': 'ድንች',
      'pepper': 'በርበሬ',
      'bell pepper': 'ቃሪያ',
      'maize': 'በቆሎ',
      'corn': 'በቆሎ',
    },
    'om': {
      'tomato': 'Timaatima',
      'potato': 'Dinichaa',
      'pepper': 'Barbaree',
      'bell pepper': 'Qariya',
      'maize': 'Boqqolloo',
      'corn': 'Boqqolloo',
    },
    'ti': {
      'tomato': 'ቲማቲም',
      'potato': 'ድንሽ',
      'pepper': 'በርበረ',
      'bell pepper': 'ቃርያ',
      'maize': 'በቆሎ',
      'corn': 'በቆሎ',
    },
    'en': {
      'tomato': 'Tomato',
      'potato': 'Potato',
      'pepper': 'Pepper',
      'bell pepper': 'Bell Pepper',
      'maize': 'Maize',
      'corn': 'Maize',
    },
  };

  static const Map<String, Map<String, String>> _roles = {
    'am': {
      'farmer': 'ገበሬ',
      'super_admin': 'ዋና አስተዳዳሪ',
      'admin': 'አስተዳዳሪ',
      'supporter': 'ድጋፍ ሰጪ',
      'expert': 'ባለሙያ',
      'field_officer': 'የመስክ ኃላፊ',
    },
    'om': {
      'farmer': 'Qonnaan bulaa',
      'super_admin': 'Bulchaa olaanaa',
      'admin': 'Bulchaa',
      'supporter': 'Deeggaraa',
      'expert': 'Ogeessa',
      'field_officer': 'Hojjetaa dirree',
    },
    'ti': {
      'farmer': 'ሓረስታይ',
      'super_admin': 'ዋና ኣስተዳዳሪ',
      'admin': 'ኣስተዳዳሪ',
      'supporter': 'ደጋፊ',
      'expert': 'ክኢላ',
      'field_officer': 'ናይ መስክ ሓላፊ',
    },
    'en': {
      'farmer': 'Farmer',
      'super_admin': 'Super Admin',
      'admin': 'Admin',
      'supporter': 'Supporter',
      'expert': 'Expert',
      'field_officer': 'Field Officer',
    },
  };

  static const Map<String, Map<String, String>> _farmTypes = {
    'am': {
      'crop': 'ሰብል',
      'mixed': 'የተቀላቀለ',
      'livestock': 'እንስሳት',
    },
    'om': {
      'crop': 'Midhaan',
      'mixed': 'Walmakaa',
      'livestock': 'Beeylada',
    },
    'ti': {
      'crop': 'ሰብል',
      'mixed': 'ዝተቐላቐለ',
      'livestock': 'እንስሳት',
    },
    'en': {
      'crop': 'Crop',
      'mixed': 'Mixed',
      'livestock': 'Livestock',
    },
  };

  static const Map<String, Map<String, String>> _soilTypes = {
    'am': {
      'clay': 'ጭቃማ',
      'sandy': 'አሸዋማ',
      'loam': 'ሎሚ',
      'silty': 'ደቃቅ አፈር',
      'peaty': 'ኦርጋኒክ አፈር',
      'chalky': 'ጭቃ-ካልክ',
      'unknown': 'ያልታወቀ',
    },
    'om': {
      'clay': 'Biyyoo maxxantuu',
      'sandy': 'Biyyoo cirrachaa',
      'loam': 'Biyyoo walqixxaa',
      'silty': 'Biyyoo xixiqqaa',
      'peaty': 'Biyyoo orgaanikii',
      'chalky': 'Biyyoo calcaarii',
      'unknown': 'Hin beekamne',
    },
    'ti': {
      'clay': 'ጭቃዊ',
      'sandy': 'ሓሸዋዊ',
      'loam': 'ሎም',
      'silty': 'ደቂቕ መሬት',
      'peaty': 'ኦርጋኒክ መሬት',
      'chalky': 'ቻኪ መሬት',
      'unknown': 'ዘይተፈልጠ',
    },
    'en': {
      'clay': 'Clay',
      'sandy': 'Sandy',
      'loam': 'Loam',
      'silty': 'Silty',
      'peaty': 'Peaty',
      'chalky': 'Chalky',
      'unknown': 'Unknown',
    },
  };


  static const Map<String, String> _severityLabel = {
    'am': 'ክብደት',
    'om': 'Cimina',
    'ti': 'ክብደት',
    'en': 'Severity',
  };
  static const Map<String, Map<String, String>> _severity = {
    'am': {
      'critical': 'እጅግ ከባድ',
      'high': 'ከፍተኛ',
      'medium': 'መካከለኛ',
      'low': 'ዝቅተኛ',
    },
    'om': {
      'critical': 'Baayyee cimaa',
      'high': 'Ol’aanaa',
      'medium': 'Giddugaleessa',
      'low': 'Gadi-aanaa',
    },
    'ti': {
      'critical': 'ኣዝዩ ሓደገኛ',
      'high': 'ልዑል',
      'medium': 'ማእከላይ',
      'low': 'ትሑት',
    },
    'en': {
      'critical': 'Critical',
      'high': 'High',
      'medium': 'Medium',
      'low': 'Low',
    },
  };

  static String status(String lang, String raw) {
    final normalizedLang = LanguageConfig.normalize(lang);
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return raw;
    return _status[normalizedLang]?[normalized] ?? _status['en']?[normalized] ?? raw;
  }

  static String severityLabel(String lang) {
    final normalizedLang = LanguageConfig.normalize(lang);
    return _severityLabel[normalizedLang] ?? _severityLabel['en']!;
  }

  static String severity(String lang, String raw) {
    final normalizedLang = LanguageConfig.normalize(lang);
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return raw;
    return _severity[normalizedLang]?[normalized] ?? _severity['en']?[normalized] ?? raw;
  }

  static String fixed(String lang, String key) {
    final normalizedLang = LanguageConfig.normalize(lang);
    return _fixed[normalizedLang]?[key] ?? _fixed['en']?[key] ?? key;
  }

  static String fixedWithParams(
    String lang,
    String key, {
    Map<String, String> params = const {},
  }) {
    var value = fixed(lang, key);
    params.forEach((k, v) {
      value = value.replaceAll('{$k}', v);
    });
    return value;
  }

  static String crop(String lang, String raw) {
    final normalizedLang = LanguageConfig.normalize(lang);
    final normalized = raw.trim().toLowerCase().replaceAll('_', ' ');
    if (normalized.isEmpty) return raw;
    return _crops[normalizedLang]?[normalized] ?? _crops['en']?[normalized] ?? raw;
  }

  static String role(String lang, String raw) {
    final normalizedLang = LanguageConfig.normalize(lang);
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return raw;
    return _roles[normalizedLang]?[normalized] ?? _roles['en']?[normalized] ?? raw;
  }

  static String farmType(String lang, String raw) {
    final normalizedLang = LanguageConfig.normalize(lang);
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return raw;
    return _farmTypes[normalizedLang]?[normalized] ?? _farmTypes['en']?[normalized] ?? raw;
  }

  static String soilType(String lang, String raw) {
    final normalizedLang = LanguageConfig.normalize(lang);
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return raw;
    return _soilTypes[normalizedLang]?[normalized] ?? _soilTypes['en']?[normalized] ?? raw;
  }
}


