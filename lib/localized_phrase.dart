import 'language_config.dart';

class Phrase {
  static const Map<String, Map<String, String>> _strings = {
    'am': {
      'offline_provisional_result': 'ኦፍላይን ጊዜያዊ ውጤት',
      'likely_issue_label': 'ሊሆን የሚችል ችግር',
      'treatment_after_verification':
          'ህክምና ማረጋገጫ ከተጠናቀቀ በኋላ ይታያል። እስከዚያው ድረስ ቁጥጥር፣ ክትትል እና ካስፈለገ የተሻለ የቅጠል ፎቶ ላይ ትኩረት ያድርጉ።',
      'offline_guidance_warning':
          'ይህ መመሪያ ጊዜያዊ (ኦፍላይን) ነው። መጠን፣ PPE፣ PHI እና REI በድጋፍ ሰጪ እስኪረጋገጥ ድረስ ፀረ ተባይ አትጠቀሙ።',
      'confidence_label': 'እምነት',
      'next_step_label': 'ቀጣይ እርምጃ',
      'actions_now': 'አሁን የሚወሰዱ እርምጃዎች',
      'what_to_do_now': 'አሁን ምን ማድረግ እንዳለብዎ',
      'what_to_avoid_now': 'አሁን ምን ማስወገድ እንዳለብዎ',
      'monitoring': 'ክትትል',
      'what_to_watch_next': 'ቀጥሎ ምን መከታተል እንዳለብዎ',
      'prevention': 'መከላከል',
      'protect_rest_of_field': 'የቀረውን ማሳ ይጠብቁ',
      'escalate_if': 'ከሆነ አሳድግ',
      'get_help_quickly_if': 'እነዚህ ካሉ ፈጥነው እገዛ ይፈልጉ',
      'before_you_treat': 'ከህክምና በፊት',
      'notes': 'ማስታወሻዎች',
      'crop_mismatch_title': 'የሰብል አለመስማማት',
      'selected_crop': 'የተመረጠ ሰብል',
      'detected_crop': 'የተገኘ ሰብል',
      'validation_failure': 'የማረጋገጫ ውድቀት',
      'code_label': 'ኮድ',
      'gate_label': 'መቆጣጠሪያ',
      'guidance_mode': 'የመመሪያ ሁኔታ',
      'reliability': 'የእምነት ደረጃ',
      'risk_level': 'የአደጋ ደረጃ',
      'reported_at': 'የተመዘገበበት ጊዜ',
      'disease_label': 'በሽታ',
      'triggered_at': 'የተነሳበት ጊዜ',
      'confidence_sentence': 'እምነት: {value}',
      'next_step_sentence': 'ቀጣይ እርምጃ: {value}',
      'disease_report_id': 'የበሽታ ሪፖርት #{id}',
      'crop_health_next_good': 'መደበኛ ክትትል ይቀጥሉ እና ምልክት ካለ ዳግም ያስካኑ።',
      'crop_health_next_warning': 'በቅርብ ይከታተሉ እና ግልጽ የቅርብ ፎቶ በመጠቀም ዳግም ያስካኑ።',
      'crop_health_next_bad': 'ወደ የበሽታ ምርመራ ሂደት ይግቡ እና ማረጋገጫ ይጠብቁ።',
      'no_leaf_detected': 'ቅጠል አልተገኘም። እባክዎ ቅጠሉን በመካከል ያድርጉ።',
      'crop_mismatch_rescan':
          'የተመረጠው ሰብል ከተገኘው ሰብል ጋር አይስማማም። እባክዎ ትክክለኛውን ሰብል እንደገና ይስካኑ።',
      'scan_rejected_validation': 'ስካኑ በማረጋገጫ ፍተሻ ተቀባይነት አላገኘም።',
      'do_not_treat_wait_feedback':
          'ህክምና አታድርጉ። የድጋፍ ሰጪ ምላሽ ይጠብቁ እና ግልጽ ፎቶዎች እንደገና ያንሱ።',
      'crop_family_mismatch_wait':
          'የተመረጠው ሰብል እና የተገኘው የበሽታ ቤተሰብ አይስማሙም። ትክክለኛውን ሰብል እንደገና ያንሱ እና የድጋፍ ሰጪ ማረጋገጫ ይጠብቁ።',
      'do_not_treat_wait_confirmation': 'አሁን ህክምና አታድርጉ። ማረጋገጫ ይጠብቁ።',
      'supporter_verification_pending':
          'የድጋፍ ሰጪ ማረጋገጫ በመጠበቅ ላይ ነው። አሁን ህክምና አታድርጉ።',
      'follow_approved_guidance': 'ለዚህ በሽታ የተፈቀደውን የህክምና መመሪያ ይከተሉ።',
      'diagnosis_rejected': 'ምርመራው ተወድቋል',
      'diagnosis_pending_review': 'ምርመራው ግምገማ በመጠበቅ ላይ ነው',
      'healthy_leaf_title': 'ቅጠሉ ጤናማ ይመስላል',
      'healthy_leaf_status': 'ጤናማ',
      'healthy_leaf_summary':
          'በዚህ ስካን ውስጥ የበሽታ ክፍል አልተገኘም። መደበኛ የማሳ ክትትል ይቀጥሉ እና ምልክቶች ከታዩ እንደገና ይስካኑ።',
      'healthy_leaf_next_step': 'አሁን ፀረ ተባይ አያስፈልግም። መደበኛ ክትትልንና ጥሩ የሰብል እንክብካቤን ይቀጥሉ።',
      'verification_pending': 'ማረጋገጫ በመጠበቅ ላይ',
      'diagnosis_confirmed_treatment_pending': 'ምርመራው ተረጋግጧል',
      'treatment_guidance_ready': 'የህክምና መመሪያ ዝግጁ ነው',
      'capture_rejected': 'የተያዘው ፎቶ ተቀባይነት አላገኘም',
      'selected_crop_mismatch': 'የተመረጠው ሰብል አይስማማም',
      'no_leaf_detected_capture_again':
          'ቅጠል አልተገኘም። እባክዎ ግልጽ ቅጠል በመመሪያ ሳጥኑ ውስጥ አስገብተው እንደገና ያንሱ።',
      'selected_detected_crop_different':
          'የተመረጠው ሰብል እና የተገኘው ሰብል የተለያዩ ናቸው። ትክክለኛውን ሰብል ይምረጡ እና እንደገና ይስካኑ።',
      'summary_rejected_no_treatment':
          'ይህ ምርመራ በድጋፍ ሰጪ ተወድቋል። ከዚህ ሪፖርት መነሻ ህክምና አታድርጉ።',
      'summary_family_mismatch_locked':
          'የተመረጠው የሰብል አውድ እና የትንበያው ቤተሰብ አይስማሙም። ምርመራው ለእጅ ማረጋገጫ ተቆልፏል።',
      'summary_unreliable': 'ምርመራው ለህክምና አሁን በቂ እምነት የለውም።',
      'summary_awaiting_verification':
          'የድጋፍ ሰጪ ማረጋገጫ በመጠበቅ ላይ ነው። አሁን ህክምና አታድርጉ።',
      'summary_confirmed_treatment_pending':
          'ምርመራው ተረጋግጧል፣ ነገር ግን ለዚህ ሰብልና በሽታ የፀረ ተባይ ሰንጠረዥ ገና ስላልተፈቀደ የህክምና መመሪያው አሁንም ተዘግቷል።',
      'summary_confirmed_advisory_treatment':
          'ምርመራው ተረጋግጧል። ከታች ያለው የህክምና መመሪያ ምክር ብቻ ነው፤ ከመርጨት በፊት በአካባቢዎ የተመዘገበ የመድሀኒት መለያ ላይ ያረጋግጡ።',
      'summary_ready': 'የተረጋገጠ ሪፖርት ለህክምና መመሪያ ዝግጁ ነው።',
      'treatment_hidden_until_verification':
          'ኬሚካላዊ የህክምና መመሪያ እስከ ማረጋገጫ ድረስ ተደብቆ ይቆያል። በዚህ ሪፖርት መሠረት አሁን ፀረ ተባይ አትርጩ።',
      'treatment_hidden_until_approved':
          'ምርመራው ተረጋግጧል፣ ነገር ግን ለዚህ ሰብልና በሽታ የፀረ ተባይ ሰንጠረዥ እስኪፈቀድ ድረስ የኬሚካል ህክምና መመሪያ አይታይም።',
      'treatment_advisory_after_confirmation':
          'ምርመራው ተረጋግጧል። ከታች ያለው የህክምና መመሪያ ምክር ብቻ ነው። ከመርጨት በፊት መጠን፣ PHI እና REI በተመዘገበ መለያ ላይ ያረጋግጡ።',
      'before_treatment_confirm':
          'ህክምና ከመፈጸምዎ በፊት፦ መጠን/መለኪያ፣ PPE፣ የመከር በፊት የሚጠበቅ ጊዜ እና የመመለሻ ጊዜን በተፈቀደ መመሪያ ያረጋግጡ።',
      'captured_leaf_mismatch': 'የተቀረጸው ቅጠል ከስካን በፊት ከተመረጠው ሰብል ጋር አይስማማም።',
      'low_confidence_recommendation':
          'እምነቱ ዝቅተኛ ነው። ከእርምጃ በፊት አዲስ እና የተሻለ ስካን ወይም የድጋፍ ሰጪ ግምገማ ይመረጣል።',
    },
    'om': {
      'offline_provisional_result': 'Bu\'aa yeroo (offline)',
      'likely_issue_label': 'Rakkoo ta\'uu danda\'u',
      'treatment_after_verification':
          'Qajeelfamni wal\'aansaa erga mirkanaa\'ee booda ni mul\'ata. Ammaaf to\'annoo, hordoffii, fi yoo barbaachise suuraa baalaa ifa ta\'e irratti xiyyeeffadhu.',
      'offline_guidance_warning':
          'Qajeelfamni kun yeroo (offline) dha. Hamma deeggarsaan ragga\'utti qoricha biifamuu hin fayyadamina.',
      'confidence_label': 'Amanamummaa',
      'next_step_label': 'Tarkaanfii itti aanu',
      'actions_now': 'Tarkaanfii yeroo ammaa',
      'what_to_do_now': 'Amma maal gochuu qabda',
      'what_to_avoid_now': 'Amma maal irraa of qusachuu qabda',
      'monitoring': 'Hordoffii',
      'what_to_watch_next': 'Itti aansuun maal hordofuu qabda',
      'prevention': 'Ittisa',
      'protect_rest_of_field': 'Dirree hafes eegi',
      'escalate_if': 'Yoo ta\'e ol guddisi',
      'get_help_quickly_if': 'Yoo kana argite dafii gargaarsa barbaadi',
      'before_you_treat': 'Wal\'aansa dura',
      'notes': 'Yaadannoowwan',
      'crop_mismatch_title': 'Wal hin fakkaannee qonnaa',
      'selected_crop': 'Qonnaa filatame',
      'detected_crop': 'Qonnaa argame',
      'validation_failure': 'Dogoggora mirkaneessaa',
      'code_label': 'Koodii',
      'gate_label': 'Balbala',
      'guidance_mode': 'Haala qajeelfamaa',
      'reliability': 'Amanamummaa',
      'risk_level': 'Sadarkaa balaa',
      'reported_at': 'Yeroo gabaafame',
      'disease_label': 'Dhukkuba',
      'triggered_at': 'Yeroo kaka\'e',
      'confidence_sentence': 'Amanamummaa: {value}',
      'next_step_sentence': 'Tarkaanfii itti aanu: {value}',
      'disease_report_id': 'Gabaasa dhukkuba #{id}',
      'crop_health_next_good':
          'Hordoffii idilee itti fufi; mallattoon yoo mul\'ate irra deebi\'i skaan godhi.',
      'crop_health_next_warning':
          'Dhiheenya irraa hordofi; suuraa ifa ta\'een irra deebi\'i skaan godhi.',
      'crop_health_next_bad':
          'Garee qorannoo dhukkubaa jalqabi; mirkaneessa eegi.',
      'no_leaf_detected': 'Baalli hin argamne. Maaloo baala sana gidduutti kaa\'i.',
      'crop_mismatch_rescan':
          'Qonnaan filatame qonnaa argame waliin hin walfakkaatu. Maaloo qonnaa sirrii irra deebi\'ii skaan godhi.',
      'scan_rejected_validation': 'Skaanniin mirkaneessa irra darbee hin fudhatamne.',
      'do_not_treat_wait_feedback':
          'Wal\'aansa hin godhin. Deebii deeggarsaa eegi fi suuraa ifa ta\'e irra deebi\'ii kaasi.',
      'crop_family_mismatch_wait':
          'Qonnaan filatame fi maatiin dhukkubaa argame wal hin simne. Qonnaa sirrii irratti irra deebi\'ii kaasi fi mirkaneessa deeggarsaa eegi.',
      'do_not_treat_wait_confirmation': 'Amma hin yaalin. Mirkaneessa eegi.',
      'supporter_verification_pending':
          'Mirkaneessi deeggartootaa eeggamaa jira. Amma wal\'aansa hin godhin.',
      'follow_approved_guidance':
          'Dhukkuba kanaaf qajeelfama wal\'aansaa ragga\'e hordofi.',
      'diagnosis_rejected': 'Bu\'aan qorannoo kufeera',
      'diagnosis_pending_review': 'Bu\'aan qorannoo gamaaggama eeggachaa jira',
      'healthy_leaf_title': 'Baalli kun fayyaa gaarii fakkaata',
      'healthy_leaf_status': 'Fayyaaleessa',
      'healthy_leaf_summary':
          'Skaan kana keessatti gosti dhukkubaa hin argamne. Hordoffii dirree itti fufi; mallattoon yoo mul\'ate irra deebi\'ii skaan godhi.',
      'healthy_leaf_next_step':
          'Amma qorichi biifamuu hin barbaachisu. Hordoffii idilee fi kunuunsa qonnaa gaarii itti fufi.',
      'verification_pending': 'Mirkaneessi eeggamaa jira',
      'diagnosis_confirmed_treatment_pending': 'Bu\'aan qorannoo mirkanaa\'eera',
      'treatment_guidance_ready': 'Qajeelfamni wal\'aansaa qophaa\'eera',
      'capture_rejected': 'Suuraan qabame hin fudhatamne',
      'selected_crop_mismatch': 'Qonnaan filatame wal hin simne',
      'no_leaf_detected_capture_again':
          'Baalli hin argamne. Maaloo baala ifa ta\'e saanduqa qajeelfamaa keessatti kaa\'ii irra deebi\'ii kaasi.',
      'selected_detected_crop_different':
          'Qonnaan filatame fi qonnaan argame garaagara. Qonnaa sirrii filadhuutii irra deebi\'ii skaan godhi.',
      'summary_rejected_no_treatment':
          'Qorannoon kun deeggartootaan kufeera. Gabaasa kana irratti hundaa\'uun wal\'aansa hin godhin.',
      'summary_family_mismatch_locked':
          'Haalli qonnaa filatame fi maatiin tilmaamaa wal hin simne. Qorannoon mirkaneessa harkaa eeggachuuf cufameera.',
      'summary_unreliable':
          'Bu\'aan qorannoo kun ammaaf wal\'aansaaf amanamaa gahaa miti.',
      'summary_awaiting_verification':
          'Mirkaneessa deeggartootaa eeggataa jira. Amma wal\'aansa hin godhin.',
      'summary_confirmed_treatment_pending':
          'Bu\'aan qorannoo mirkanaa\'eera, garuu gabateen qoricha qonnaa fi dhukkuba kanaaf hin raggaane; kanaaf qajeelfamni wal\'aansaa ammallee cufameera.',
      'summary_confirmed_advisory_treatment':
          'Bu\'aan qorannoo mirkanaa\'eera. Qajeelfamni wal\'aansaa armaan gadi jiru gorsa qofa; dura kaayyoo, PHI, fi REI irratti asxaa qorichaa galmaa\'ee jiru mirkaneessi.',
      'summary_ready': 'Gabaasni mirkanaa\'e qajeelfama wal\'aansaaaf qophaa\'eera.',
      'treatment_hidden_until_verification':
          'Qajeelfamni wal\'aansa keemikaalaa hanga mirkaneessatti dhokfamee jira. Gabaasa kana irratti hundaa\'uun amma qoricha hin biifin.',
      'treatment_hidden_until_approved':
          'Bu\'aan qorannoo mirkanaa\'eera, garuu gabateen qoricha qonnaa fi dhukkuba kanaaf hanga ragga\'utti qajeelfamni wal\'aansa keemikaalaa hin mul\'atu.',
      'treatment_advisory_after_confirmation':
          'Bu\'aan qorannoo mirkanaa\'eera. Qajeelfamni armaan gadi jiru gorsa qofa. Osoo hin biifin dura hanga, PHI, fi REI asxaa qorichaa galmaa\'ee irratti mirkaneessi.',
      'before_treatment_confirm':
          'Wal\'aansa dura: hanga/yuunitii, PPE, yeroo omisha haammachuu dura eeggamu, fi yeroo deebi\'anii seenuu qajeelfama ragga\'e irraa mirkaneessi.',
      'captured_leaf_mismatch':
          'Baalli kaafame qonnaa skaana dura filatame waliin hin simne.',
      'low_confidence_recommendation':
          'Amanamummaan gadi aanaa dha. Tarkaanfii dura skaan haaraa ifa ta\'e yookaan gamaaggama deeggartootaa filachuun wayya.',
    },
    'ti': {
      'offline_provisional_result': 'ኦፍላይን ግዝያዊ ውጽኢት',
      'likely_issue_label': 'ክኸውን ዝኽእል ጸገም',
      'treatment_after_verification':
          'መምርሒ ሕክምና ድሕሪ ምርግጋፅ ክርአ እዩ። ክሳብ ሽዑ ግን ኣብ ምቁፅፃር፣ ክትትል፣ እንተድኣ ኣድልዩ ድማ ኣብ ዝያዳ ንፁር ስእሊ ቅጠል ኣትኩሩ።',
      'offline_guidance_warning':
          'እዚ መምርሒ ግዝያዊ (ኦፍላይን) እዩ። ብደጋፊ ክሳብ ዝፀደቐ ፀረ-ባልዕ ኣይትጠቐሙ።',
      'confidence_label': 'እምነት',
      'next_step_label': 'ዝቕፅል ስጉምቲ',
      'actions_now': 'ሕጂ ዝውሰዱ ስጉምታት',
      'what_to_do_now': 'ሕጂ እንታይ ክትገብሩ ኣለኩም',
      'what_to_avoid_now': 'ሕጂ እንታይ ከትውግዱ ኣለኩም',
      'monitoring': 'ክትትል',
      'what_to_watch_next': 'ቀፂሉ እንታይ ክትከታተሉ ኣለኩም',
      'prevention': 'መከላኸሊ',
      'protect_rest_of_field': 'ነቲ ዝተረፈ ማሳ ሓልዉ',
      'escalate_if': 'እንተኾነ ኣርእዮ',
      'get_help_quickly_if': 'እዚ እንተርኢኹም ቀልጢፍኩም ሓገዝ ድለዩ',
      'before_you_treat': 'ቅድሚ ሕክምና',
      'notes': 'መዘኻኸሪታት',
      'crop_mismatch_title': 'ዘይምስምማዕ ዝራእቲ',
      'selected_crop': 'ዝተመረፀ ዝራእቲ',
      'detected_crop': 'ዝተረኸበ ዝራእቲ',
      'validation_failure': 'ምርግጋፅ ተፈሺሉ',
      'code_label': 'ኮድ',
      'gate_label': 'ጌት',
      'guidance_mode': 'ኣገባብ መምርሒ',
      'reliability': 'እሙንነት',
      'risk_level': 'ደረጃ ሓደጋ',
      'reported_at': 'ዝተመዝገበሉ ግዜ',
      'disease_label': 'ሕማም',
      'triggered_at': 'ዝተንቀሳቐሰሉ ግዜ',
      'confidence_sentence': 'እምነት: {value}',
      'next_step_sentence': 'ዝቕፅል ስጉምቲ: {value}',
      'disease_report_id': 'ፀብፃብ ሕማም #{id}',
      'crop_health_next_good':
          'ናይ መደበኛ ክትትል ቀፅል፣ ምልክት እንተተራእዩ እንደገና ስካን ግበር።',
      'crop_health_next_warning':
          'ብቐረባ ክትትል ግበር፣ ብዝግልፅ ቕርብ ስእሊ እንደገና ስካን ግበር።',
      'crop_health_next_bad':
          'ናብ ሕማም ምርመራ ኣብፅሕ እና ምርግጋፅ ተፀበይ።',
      'no_leaf_detected': 'ቅጠል ኣይተረኸበን። በጃኹም ነቲ ቅጠል ኣብ ማእከል ኣእትዉ።',
      'crop_mismatch_rescan':
          'ዝተመረፀ ዝራእቲ ምስ ዝተረኸበ ዝራእቲ ኣይሰማማዕን። በጃኹም ነቲ ትኽክለኛ ዝራእቲ እንደገና ስካን ግበሩ።',
      'scan_rejected_validation': 'ስካኑ ብመርግጋፅ መፈተኒ ኣይተቐበለን።',
      'do_not_treat_wait_feedback':
          'ሕክምና ኣይትግበሩ። ምላሽ ደጋፊ ተፀበዩ እና ዝያዳ ንፁር ስእሊ እንደገና ኣንስኡ።',
      'crop_family_mismatch_wait':
          'ዝተመረፀ ዝራእቲን ዝተረኸበ ስድራ ሕማምን ኣይሰማማዕን። ኣብ ትኽክለኛ ዝራእቲ እንደገና ኣንስኡን ምርግጋፅ ደጋፊ ተፀበዩን።',
      'do_not_treat_wait_confirmation': 'ሕጂ ሕክምና ኣይትግበሩ። ምርግጋፅ ተፀበዩ።',
      'supporter_verification_pending':
          'ምርግጋፅ ደጋፊ ይፅበ ኣሎ። ሕጂ ሕክምና ኣይትግበሩ።',
      'follow_approved_guidance': 'ነዚ ሕማም ዝፀደቐ መምርሒ ሕክምና ተኸተሉ።',
      'diagnosis_rejected': 'ውፅኢት ምርመራ ተነፂጉ',
      'diagnosis_pending_review': 'ውፅኢት ምርመራ ግምገማ ይፅበ ኣሎ',
      'healthy_leaf_title': 'ቅጠሉ ጥዑይ ይመስል',
      'healthy_leaf_status': 'ጥዑይ',
      'healthy_leaf_summary':
          'ኣብዚ ስካን ግዜ ክፍሊ ሕማም ኣይተረኸበን። መደበኛ ክትትል ቀፅሉ እና ምልክታት እንተተራእዩ እንደገና ስካን ግበሩ።',
      'healthy_leaf_next_step':
          'ሕጂ ፀረ ባልዕ ኣየድልን። መደበኛ ክትትልን ፅቡቕ ክንክን ዝራእትን ቀፅሉ።',
      'verification_pending': 'ምርግጋፅ ይፅበ ኣሎ',
      'diagnosis_confirmed_treatment_pending': 'ውፅኢት ምርመራ ተረጋጊፁ',
      'treatment_guidance_ready': 'መምርሒ ሕክምና ተዳልዩ ኣሎ',
      'capture_rejected': 'ዝተቐረፀ ስእሊ ኣይተቐበለን',
      'selected_crop_mismatch': 'ዝተመረፀ ዝራእቲ ኣይሰማማዕን',
      'no_leaf_detected_capture_again':
          'ቅጠል ኣይተረኸበን። በጃኹም ንፁር ቅጠል ኣብ ሳጹን መምርሒ ኣእትዉ እና እንደገና ኣንስኡ።',
      'selected_detected_crop_different':
          'ዝተመረፀ ዝራእቲን ዝተረኸበ ዝራእቲን ዝተፈላለዩ እዮም። ነቲ ትኽክለኛ ዝራእቲ ምረፁ እና እንደገና ስካን ግበሩ።',
      'summary_rejected_no_treatment':
          'እዚ ምርመራ ብደጋፊ ተነፂጉ እዩ። ካብዚ ፀብፃብ ተበጊስኩም ሕክምና ኣይትግበሩ።',
      'summary_family_mismatch_locked':
          'ዝተመረፀ ኣውድ ዝራእቲን ስድራ ትንበያን ኣይሰማምዑን። ምርመራ ንምርግጋፅ ብኢድ ተዓፂዩ ኣሎ።',
      'summary_unreliable':
          'እዚ ውፅኢት ምርመራ ንሕክምና እዋናዊ ብቑዕ እምነት የብሉን።',
      'summary_awaiting_verification':
          'ምርግጋፅ ደጋፊ ይፅበ ኣሎ። ሕጂ ሕክምና ኣይትግበሩ።',
      'summary_confirmed_treatment_pending':
          'ውፅኢት ምርመራ ተረጋጊፁ እዩ፣ ግን ናይዚ ዝራእቲን ሕማምን ጠረጴዛ ፀረ-ባልዕ ገና ኣይፀደቐን፤ ስለዚ መምርሒ ሕክምና ክሳብ ሕጂ ተዓፂዩ ኣሎ።',
      'summary_confirmed_advisory_treatment':
          'ውፅኢት ምርመራ ተረጋጊፁ እዩ። እቲ ኣብ ታሕቲ ዘሎ መምርሒ ሕክምና ምኽሪ ጥራይ እዩ፤ ቅድሚ ምንፃፍ ኣብ ከባቢኹም ዝተመዝገበ ምልክት መድሃኒት ላዕሊ ኣረጋግፁ።',
      'summary_ready': 'ዝተረጋገፀ ፀብፃብ ንመምርሒ ሕክምና ድሉው እዩ።',
      'treatment_hidden_until_verification':
          'መምርሒ ኬሚካላዊ ሕክምና ክሳብ ምርግጋፅ ተሓቢኡ ይቕፅል። ብዚ ፀብፃብ መሰረት ሕጂ ፀረ-ባልዕ ኣይትንፅፉ።',
      'treatment_hidden_until_approved':
          'ውፅኢት ምርመራ ተረጋጊፁ እዩ፣ ግን ናይዚ ዝራእቲን ሕማምን ጠረጴዛ ፀረ-ባልዕ ክሳብ ዝፀድቕ መምርሒ ኬሚካላዊ ሕክምና ኣይክርአን እዩ።',
      'treatment_advisory_after_confirmation':
          'ውፅኢት ምርመራ ተረጋጊፁ እዩ። እቲ ኣብ ታሕቲ ዘሎ መምርሒ ሕክምና ምኽሪ ጥራይ እዩ። ቅድሚ ምንፃፍ መጠን፣ PHI እና REI ኣብ ዝተመዝገበ ምልክት ኣረጋግፁ።',
      'before_treatment_confirm':
          'ቅድሚ ሕክምና፦ መጠን/ዩኒት፣ PPE፣ ናይ ቅድሚ መከር ግዜ ምፅባይ፣ እና ናይ ድሕሪ ምምላስ ግዜ ካብ ዝፀደቐ መምርሒ ኣረጋግፁ።',
      'captured_leaf_mismatch':
          'እቲ ዝተቐረፀ ቅጠል ምስቲ ቅድሚ ስካን ዝተመረፀ ዝራእቲ ኣይሰማማዕን።',
      'low_confidence_recommendation':
          'እምነቱ ትሑት እዩ። ቅድሚ ስጉምቲ ሓድሽ ንፁር ስካን ወይ ግምገማ ደጋፊ ምምራፅ ይሓይሽ።',
    },
    'en': {
      'offline_provisional_result': 'Offline provisional result',
      'likely_issue_label': 'Likely issue',
      'treatment_after_verification':
          'Treatment will appear after verification. For now, focus on containment, monitoring, and a clearer leaf photo if needed.',
      'offline_guidance_warning':
          'This guidance is provisional (offline). Do not spray pesticides unless dosage, PPE, PHI, and REI are confirmed by supporter-approved guidance.',
      'confidence_label': 'Confidence',
      'next_step_label': 'Next step',
      'actions_now': 'Actions now',
      'what_to_do_now': 'What to do now',
      'what_to_avoid_now': 'What to avoid for now',
      'monitoring': 'Monitoring',
      'what_to_watch_next': 'What to watch next',
      'prevention': 'Prevention',
      'protect_rest_of_field': 'Protect the rest of the field',
      'escalate_if': 'Escalate if',
      'get_help_quickly_if': 'Get help quickly if',
      'before_you_treat': 'Before you treat',
      'notes': 'Notes',
      'crop_mismatch_title': 'Crop mismatch',
      'selected_crop': 'Selected crop',
      'detected_crop': 'Detected crop',
      'validation_failure': 'Validation failure',
      'code_label': 'Code',
      'gate_label': 'Gate',
      'guidance_mode': 'Guidance mode',
      'reliability': 'Reliability',
      'risk_level': 'Risk level',
      'reported_at': 'Reported at',
      'disease_label': 'Disease',
      'triggered_at': 'Triggered at',
      'confidence_sentence': 'Confidence: {value}',
      'next_step_sentence': 'Next step: {value}',
      'disease_report_id': 'Disease Report #{id}',
      'crop_health_next_good':
          'Continue routine monitoring and rescan if symptoms appear.',
      'crop_health_next_warning':
          'Monitor closely and rescan with a clearer close-up image.',
      'crop_health_next_bad':
          'Start disease-check flow and wait for verification.',
      'no_leaf_detected':
          'No leaf detected. Please center the leaf in the frame.',
      'crop_mismatch_rescan':
          'Selected crop does not match detected crop. Please rescan the correct crop.',
      'scan_rejected_validation': 'Scan was rejected by validation checks.',
      'do_not_treat_wait_feedback':
          'Do not apply treatment. Wait for supporter feedback and retake clearer images.',
      'crop_family_mismatch_wait':
          'Selected crop and detected disease family do not match. Retake on the correct crop and wait supporter verification.',
      'do_not_treat_wait_confirmation':
          'Do not treat yet. Wait for supporter confirmation.',
      'supporter_verification_pending':
          'Supporter verification is pending. Avoid treatment now.',
      'follow_approved_guidance':
          'Follow approved treatment guidance for this disease.',
      'diagnosis_rejected': 'Diagnosis rejected',
      'diagnosis_pending_review': 'Diagnosis pending review',
      'healthy_leaf_title': 'Leaf appears healthy',
      'healthy_leaf_status': 'Healthy',
      'healthy_leaf_summary':
          'No disease class was found in this scan. Keep routine field monitoring and rescan if symptoms appear.',
      'healthy_leaf_next_step':
          'No pesticide is needed now. Continue scouting and good crop care.',
      'verification_pending': 'Verification pending',
      'diagnosis_confirmed_treatment_pending': 'Diagnosis confirmed',
      'treatment_guidance_ready': 'Treatment guidance ready',
      'capture_rejected': 'Capture rejected',
      'selected_crop_mismatch': 'Selected crop mismatch',
      'no_leaf_detected_capture_again':
          'No leaf detected. Please center a clear leaf in the guide box and capture again.',
      'selected_detected_crop_different':
          'Selected crop and detected crop are different. Select the correct crop and rescan.',
      'summary_rejected_no_treatment':
          'Supporter rejected this diagnosis. Do not apply treatment from this report.',
      'summary_family_mismatch_locked':
          'Selected crop context and prediction family differ. Diagnosis is locked for manual verification.',
      'summary_unreliable':
          'Diagnosis is not reliable enough for treatment yet.',
      'summary_awaiting_verification':
          'Awaiting supporter verification. Do not apply treatment yet.',
      'summary_confirmed_treatment_pending':
          'Diagnosis was confirmed, but pesticide guidance is still locked because this crop and disease treatment table has not been approved yet.',
      'summary_confirmed_advisory_treatment':
          'Diagnosis was confirmed. Treatment guidance below is advisory and must be checked against a locally registered product label before spraying.',
      'summary_ready': 'Verified report ready for treatment guidance.',
      'treatment_hidden_until_verification':
          'Chemical treatment guidance is hidden until verification. Do not spray pesticides based on this report yet.',
      'treatment_hidden_until_approved':
          'Diagnosis is confirmed, but chemical treatment guidance is still hidden until the pesticide table for this crop and disease is approved.',
      'treatment_advisory_after_confirmation':
          'Diagnosis is confirmed. Treatment guidance below is advisory. Confirm the registered product label for dosage, PHI, and REI before spraying.',
      'before_treatment_confirm':
          'Before applying treatment: confirm dosage/unit, PPE, pre-harvest interval, and re-entry interval from supporter-approved guidance.',
      'captured_leaf_mismatch':
          'The captured leaf does not match the crop selected before scan.',
      'low_confidence_recommendation':
          'Low confidence. Prefer a new clearer scan or supporter review before action.',
    },
  };

  static String t(
    String lang,
    String key, {
    Map<String, String> params = const {},
  }) {
    final normalized = LanguageConfig.normalize(lang);
    final localized = _strings[normalized]?[key];
    final amharic = _strings['am']?[key];
    final english = _strings['en']?[key];

    final bool looksLikeEnglishPlaceholder =
        normalized != 'en' &&
        localized != null &&
        english != null &&
        localized == english;

    final template = looksLikeEnglishPlaceholder
        ? (amharic ?? localized)
        : (localized ?? amharic ?? english ?? key);
    if (params.isEmpty) return template;
    var result = template;
    params.forEach((k, v) {
      result = result.replaceAll('{$k}', v);
    });
    return result;
  }
}
