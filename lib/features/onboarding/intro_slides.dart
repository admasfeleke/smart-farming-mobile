import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../language_config.dart';
import '../../language_store.dart';
import '../../widgets/farm_ui.dart';

class IntroSlides extends StatefulWidget {
  const IntroSlides({super.key});

  @override
  State<IntroSlides> createState() => _IntroSlidesState();
}

class _IntroSlidesState extends State<IntroSlides> {
  final PageController _controller = PageController();
  int _index = 0;

  List<Map<String, dynamic>> _slidesFor(String lang) {
    final l = LanguageConfig.normalize(lang);
    final strings = _localizedSlides[l] ?? _localizedSlides['en']!;
    return <Map<String, dynamic>>[
      {
        'title': strings['title_1']!,
        'desc': strings['desc_1']!,
        'icon': Icons.camera_alt_outlined,
      },
      {
        'title': strings['title_2']!,
        'desc': strings['desc_2']!,
        'icon': Icons.phone_android_outlined,
      },
      {
        'title': strings['title_3']!,
        'desc': strings['desc_3']!,
        'icon': Icons.sync_outlined,
      },
    ];
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _next() {
    final slides = _slidesFor(LanguageStore.notifier.value);
    if (_index < slides.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = LanguageStore.notifier.value;
    final slides = _slidesFor(lang);
    final strings = _localizedSlides[LanguageConfig.normalize(lang)] ?? _localizedSlides['en']!;
    return Scaffold(
      appBar: AppBar(
        actions: [TextButton(onPressed: _skip, child: Text(strings['skip']!))],
      ),
      body: SafeArea(
        child: FarmSurface(
          padding: EdgeInsets.zero,
          child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: slides.length,
                itemBuilder: (context, i) {
                  final slide = slides[i];
                  return Padding(
                    padding: const EdgeInsets.all(22),
                    child: FarmHeroCard(
                      imageAsset: i == 0
                          ? 'assets/images/crops/tomato.jpg'
                          : i == 1
                              ? 'assets/images/crops/potato.jpg'
                              : 'assets/images/crops/maize.jpg',
                      eyebrow: 'Smart Farming Ethiopia',
                      title: slide['title'] as String,
                      body: slide['desc'] as String,
                      trailing: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCFF36A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          slide['icon'] as IconData,
                          color: const Color(0xFF15210B),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                slides.length,
                (i) => Container(
                  margin: const EdgeInsets.all(4),
                  width: _index == i ? 12 : 8,
                  height: _index == i ? 12 : 8,
                  decoration: BoxDecoration(
                    color: _index == i ? theme.colorScheme.primary : Colors.grey[300],
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: Text(_index == slides.length - 1 ? strings['start']! : strings['next']!),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

const Map<String, Map<String, String>> _localizedSlides = {
  'am': {
    'title_1': 'የቅጠል በሽታን ፈጥነው ይለዩ',
    'desc_1': 'የተጎዳ ቅጠል ፎቶ አንስተው ምናልባት ያለውን ችግኝ ያውቁ።',
    'title_2': 'ከኢንተርኔት ውጭም ያስቀምጡ',
    'desc_2': 'ውጤቶችን በመሣሪያው ላይ ያስቀምጡ እና ኔትወርክ ሲመለስ ይልኩ።',
    'title_3': 'ከማረጋገጥ በኋላ ህክምና ይክፈቱ',
    'desc_3': 'አስቸኳይ እርምጃን ይውሰዱ፣ የመድሀኒት መመሪያ ግን ከማረጋገጥ በኋላ ይዩ።',
    'skip': 'ዝለል',
    'next': 'ቀጣይ',
    'start': 'እንጀምር',
  },
  'om': {
    'title_1': 'Dhukkuba baalaa saffisaan adda baasi',
    'desc_1': 'Suuraa baalaa miidhame kaasiitii rakkoo taʼuu malu adda baasi.',
    'title_2': 'Internet malee illee kuusi',
    'desc_2': 'Buʼaawwan meeshaa irratti kuusi; yeroo network deebiʼu ni erga.',
    'title_3': 'Erga mirkanaaʼee booda qajeelfama qorichaa argadhu',
    'desc_3': 'Tarkaanfii hatattamaa fudhadhu; qajeelfamni qorichaa immoo erga mirkanaaʼee booda bifa sirriin ni mulʼata.',
    'skip': 'Irra darbi',
    'next': 'Itti aanu',
    'start': 'Haa jalqabnu',
  },
  'ti': {
    'title_1': 'ሕማም ቆጽሊ ብቕልጡፍ ለሊ',
    'desc_1': 'ስእሊ ዝተጎድአ ቆጽሊ ኣንስእ እሞ ዘሎ ጸገም እንታይ ምዃኑ ፈልጥ።',
    'title_2': 'ካብ ኢንተርነት ወጻኢ እውን ኣቐምጥ',
    'desc_2': 'ውጽኢት ኣብ መሳርሒ ኣቐምጥ፣ ርክብ ምስ ተመልሰ ክልእኽ እዩ።',
    'title_3': 'ድሕሪ ምርግጋጽ ሕክምና ርአ',
    'desc_3': 'ቅልጡፍ ስጉምቲ ውሰድ፣ ናይ መድሃኒት መምርሒ ግን ድሕሪ ምርግጋጽ ጥራይ ትርኢ።',
    'skip': 'ሕለፍ',
    'next': 'ቀጺሉ',
    'start': 'ንጀምር',
  },
  'en': {
    'title_1': 'Detect leaf disease quickly',
    'desc_1': 'Take a photo of an affected leaf and see the likely issue fast.',
    'title_2': 'Save results even without internet',
    'desc_2': 'Keep scan results on this device and send them when connection returns.',
    'title_3': 'Unlock treatment after verification',
    'desc_3': 'Take safe immediate action now. Treatment guidance appears after verification.',
    'skip': 'Skip',
    'next': 'Next',
    'start': 'Let\'s Start',
  },
};
