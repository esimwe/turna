part of '../main.dart';

enum _TurnaAuthStep { welcome, phone, otp }

class _TurnaCountry {
  const _TurnaCountry({
    required this.iso,
    required this.name,
    required this.dialCode,
  });

  final String iso;
  final String name;
  final String dialCode;
}

const List<_TurnaCountry> _kTurnaCountries = [
  _TurnaCountry(iso: 'TR', name: 'Türkiye', dialCode: '+90'),
  _TurnaCountry(iso: 'GB', name: 'Birleşik Krallık', dialCode: '+44'),
  _TurnaCountry(iso: 'US', name: 'Amerika Birleşik Devletleri', dialCode: '+1'),
  _TurnaCountry(iso: 'CA', name: 'Kanada', dialCode: '+1'),
  _TurnaCountry(iso: 'DE', name: 'Almanya', dialCode: '+49'),
  _TurnaCountry(iso: 'FR', name: 'Fransa', dialCode: '+33'),
  _TurnaCountry(iso: 'NL', name: 'Hollanda', dialCode: '+31'),
  _TurnaCountry(iso: 'BE', name: 'Belçika', dialCode: '+32'),
  _TurnaCountry(iso: 'CH', name: 'İsviçre', dialCode: '+41'),
  _TurnaCountry(iso: 'AT', name: 'Avusturya', dialCode: '+43'),
  _TurnaCountry(iso: 'ES', name: 'İspanya', dialCode: '+34'),
  _TurnaCountry(iso: 'IT', name: 'İtalya', dialCode: '+39'),
  _TurnaCountry(iso: 'IE', name: 'İrlanda', dialCode: '+353'),
  _TurnaCountry(iso: 'SE', name: 'İsveç', dialCode: '+46'),
  _TurnaCountry(iso: 'NO', name: 'Norveç', dialCode: '+47'),
  _TurnaCountry(iso: 'DK', name: 'Danimarka', dialCode: '+45'),
  _TurnaCountry(iso: 'FI', name: 'Finlandiya', dialCode: '+358'),
  _TurnaCountry(iso: 'PL', name: 'Polonya', dialCode: '+48'),
  _TurnaCountry(iso: 'CZ', name: 'Çekya', dialCode: '+420'),
  _TurnaCountry(iso: 'RO', name: 'Romanya', dialCode: '+40'),
  _TurnaCountry(iso: 'BG', name: 'Bulgaristan', dialCode: '+359'),
  _TurnaCountry(iso: 'GR', name: 'Yunanistan', dialCode: '+30'),
  _TurnaCountry(iso: 'CY', name: 'Kibris', dialCode: '+357'),
  _TurnaCountry(iso: 'UA', name: 'Ukrayna', dialCode: '+380'),
  _TurnaCountry(iso: 'RU', name: 'Rusya', dialCode: '+7'),
  _TurnaCountry(iso: 'AZ', name: 'Azerbaycan', dialCode: '+994'),
  _TurnaCountry(iso: 'GE', name: 'Gurcistan', dialCode: '+995'),
  _TurnaCountry(iso: 'AM', name: 'Ermenistan', dialCode: '+374'),
  _TurnaCountry(iso: 'AE', name: 'Birleşik Arap Emirlikleri', dialCode: '+971'),
  _TurnaCountry(iso: 'SA', name: 'Suudi Arabistan', dialCode: '+966'),
  _TurnaCountry(iso: 'QA', name: 'Katar', dialCode: '+974'),
  _TurnaCountry(iso: 'KW', name: 'Kuveyt', dialCode: '+965'),
  _TurnaCountry(iso: 'BH', name: 'Bahreyn', dialCode: '+973'),
  _TurnaCountry(iso: 'OM', name: 'Umman', dialCode: '+968'),
  _TurnaCountry(iso: 'IQ', name: 'Irak', dialCode: '+964'),
  _TurnaCountry(iso: 'JO', name: 'Ürdün', dialCode: '+962'),
  _TurnaCountry(iso: 'LB', name: 'Lübnan', dialCode: '+961'),
  _TurnaCountry(iso: 'EG', name: 'Mısır', dialCode: '+20'),
  _TurnaCountry(iso: 'TN', name: 'Tunus', dialCode: '+216'),
  _TurnaCountry(iso: 'DZ', name: 'Cezayir', dialCode: '+213'),
  _TurnaCountry(iso: 'MA', name: 'Fas', dialCode: '+212'),
  _TurnaCountry(iso: 'PK', name: 'Pakistan', dialCode: '+92'),
  _TurnaCountry(iso: 'IN', name: 'Hindistan', dialCode: '+91'),
  _TurnaCountry(iso: 'CN', name: 'Çin', dialCode: '+86'),
  _TurnaCountry(iso: 'JP', name: 'Japonya', dialCode: '+81'),
  _TurnaCountry(iso: 'KR', name: 'Güney Kore', dialCode: '+82'),
  _TurnaCountry(iso: 'ID', name: 'Endonezya', dialCode: '+62'),
  _TurnaCountry(iso: 'MY', name: 'Malezya', dialCode: '+60'),
  _TurnaCountry(iso: 'SG', name: 'Singapur', dialCode: '+65'),
  _TurnaCountry(iso: 'TH', name: 'Tayland', dialCode: '+66'),
  _TurnaCountry(iso: 'VN', name: 'Vietnam', dialCode: '+84'),
  _TurnaCountry(iso: 'AU', name: 'Avustralya', dialCode: '+61'),
  _TurnaCountry(iso: 'NZ', name: 'Yeni Zelanda', dialCode: '+64'),
  _TurnaCountry(iso: 'BR', name: 'Brezilya', dialCode: '+55'),
  _TurnaCountry(iso: 'AR', name: 'Arjantin', dialCode: '+54'),
  _TurnaCountry(iso: 'MX', name: 'Meksika', dialCode: '+52'),
  _TurnaCountry(iso: 'ZA', name: 'Güney Afrika', dialCode: '+27'),
  _TurnaCountry(iso: 'NG', name: 'Nijerya', dialCode: '+234'),
  _TurnaCountry(iso: 'KE', name: 'Kenya', dialCode: '+254'),
  _TurnaCountry(iso: 'ET', name: 'Etiyopya', dialCode: '+251'),
];

class TurnaPhoneAuthPage extends StatefulWidget {
  const TurnaPhoneAuthPage({super.key, required this.onAuthenticated});

  final void Function(AuthSession session) onAuthenticated;

  @override
  State<TurnaPhoneAuthPage> createState() => _TurnaPhoneAuthPageState();
}

class _TurnaPhoneAuthPageState extends State<TurnaPhoneAuthPage> {
  static const _savedCountryIsoKey = 'turna_auth_country_iso';
  static const _savedDialCodeDigitsKey = 'turna_auth_dial_code_digits';

  final TextEditingController _dialCodeController = TextEditingController();
  final TextEditingController _nationalNumberController =
      TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  _TurnaAuthStep _step = _TurnaAuthStep.welcome;
  _TurnaCountry? _selectedCountry;
  String? _requestedPhone;
  bool _requestingOtp = false;
  bool _verifyingOtp = false;
  int _retryAfterSeconds = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _selectedCountry = _detectFallbackCountry();
    _dialCodeController.text =
        _selectedCountry?.dialCode.replaceFirst('+', '') ?? '90';
    _dialCodeController.addListener(_handleDialCodeChanged);
    _nationalNumberController.addListener(_refresh);
    _otpController.addListener(_handleOtpChanged);
    unawaited(_restoreSavedCountry());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _dialCodeController.removeListener(_handleDialCodeChanged);
    _nationalNumberController.removeListener(_refresh);
    _otpController.removeListener(_handleOtpChanged);
    _dialCodeController.dispose();
    _nationalNumberController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _restoreSavedCountry() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIso = prefs.getString(_savedCountryIsoKey);
    final savedDigits = prefs.getString(_savedDialCodeDigitsKey);
    if (!mounted) return;

    final byIso = savedIso == null
        ? null
        : () {
            final matches = _kTurnaCountries
                .where((item) => item.iso == savedIso)
                .toList();
            return matches.isEmpty ? null : matches.first;
          }();
    if (byIso != null) {
      setState(() {
        _selectedCountry = byIso;
        _dialCodeController.text = byIso.dialCode.replaceFirst('+', '');
      });
      return;
    }

    if (savedDigits != null && savedDigits.trim().isNotEmpty) {
      _dialCodeController.text = savedDigits.trim();
    }
  }

  _TurnaCountry _detectFallbackCountry() {
    final localeCountryCode = ui.PlatformDispatcher.instance.locale.countryCode
        ?.toUpperCase();
    if (localeCountryCode != null) {
      final matches = _kTurnaCountries
          .where((item) => item.iso == localeCountryCode)
          .toList();
      final byIso = matches.isEmpty ? null : matches.first;
      if (byIso != null) {
        return byIso;
      }
    }
    return _kTurnaCountries.firstWhere((item) => item.iso == 'TR');
  }

  String get _dialCode =>
      '+${_dialCodeController.text.replaceAll(RegExp(r'\D+'), '')}';

  String get _nationalNumber =>
      _nationalNumberController.text.replaceAll(RegExp(r'\D+'), '');

  bool get _canContinuePhoneStep =>
      _selectedCountry != null &&
      _dialCodeController.text.trim().isNotEmpty &&
      _nationalNumber.length >= 6;

  void _handleDialCodeChanged() {
    final digits = _dialCodeController.text.replaceAll(RegExp(r'\D+'), '');
    final normalized = digits;
    if (_dialCodeController.text != normalized) {
      _dialCodeController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      return;
    }

    final current = _selectedCountry;
    final matching = _kTurnaCountries
        .where((item) => item.dialCode == '+$normalized')
        .toList();

    if (matching.isEmpty) {
      if (_selectedCountry != null && mounted) {
        setState(() => _selectedCountry = null);
      } else {
        _refresh();
      }
      return;
    }

    final next =
        current != null && matching.any((item) => item.iso == current.iso)
        ? current
        : matching.first;
    if (_selectedCountry?.iso != next.iso && mounted) {
      setState(() => _selectedCountry = next);
    } else {
      _refresh();
    }
  }

  void _handleOtpChanged() {
    final digits = _otpController.text.replaceAll(RegExp(r'\D+'), '');
    if (_otpController.text != digits) {
      _otpController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
      return;
    }

    if (digits.length == 6 && !_verifyingOtp) {
      unawaited(_verifyOtp(digits));
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _persistCountrySelection(_TurnaCountry? country) async {
    final prefs = await SharedPreferences.getInstance();
    if (country == null) {
      await prefs.remove(_savedCountryIsoKey);
      await prefs.setString(
        _savedDialCodeDigitsKey,
        _dialCodeController.text.replaceAll(RegExp(r'\D+'), ''),
      );
      return;
    }

    await prefs.setString(_savedCountryIsoKey, country.iso);
    await prefs.setString(
      _savedDialCodeDigitsKey,
      country.dialCode.replaceFirst('+', ''),
    );
  }

  String _formatPhonePreview({
    required String countryIso,
    required String dialCode,
    required String nationalNumber,
  }) {
    List<int> pattern;
    switch (countryIso.toUpperCase()) {
      case 'TR':
        pattern = const [3, 3, 2, 2];
        break;
      case 'GB':
        pattern = const [4, 6];
        break;
      case 'US':
      case 'CA':
        pattern = const [3, 3, 4];
        break;
      default:
        pattern = const [3, 3, 4];
        break;
    }

    final chunks = <String>[];
    var cursor = 0;
    for (final size in pattern) {
      if (cursor >= nationalNumber.length) break;
      final end = math.min(cursor + size, nationalNumber.length);
      chunks.add(nationalNumber.substring(cursor, end));
      cursor = end;
    }
    if (cursor < nationalNumber.length) {
      chunks.add(nationalNumber.substring(cursor));
    }

    return '$dialCode ${chunks.join(' ')}'.trim();
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<_TurnaCountry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _TurnaCountryPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedCountry = picked;
      _dialCodeController.text = picked.dialCode.replaceFirst('+', '');
    });
    await _persistCountrySelection(picked);
  }

  Future<void> _confirmPhone() async {
    if (!_canContinuePhoneStep || _selectedCountry == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        final preview = _formatPhonePreview(
          countryIso: _selectedCountry!.iso,
          dialCode: _selectedCountry!.dialCode,
          nationalNumber: _nationalNumber,
        );
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 272),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bu numara doğru mu?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF3C4043),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    preview,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                      color: Color(0xFF202124),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Düzenle'),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Evet'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (approved == true) {
      await _requestOtp();
    }
  }

  Future<void> _requestOtp() async {
    if (_selectedCountry == null || _requestingOtp) return;
    setState(() => _requestingOtp = true);
    _showBlockingProgress('Kod gönderiliyor...');

    try {
      final ticket = await AuthApi.requestOtp(
        countryIso: _selectedCountry!.iso,
        dialCode: _dialCode,
        nationalNumber: _nationalNumber,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _persistCountrySelection(_selectedCountry);
      _startRetryCountdown(ticket.retryAfterSeconds);
      setState(() {
        _requestedPhone = ticket.phone;
        _step = _TurnaAuthStep.otp;
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _otpFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _showErrorDialog(_friendlyError(error.toString()));
    } finally {
      if (mounted) {
        setState(() => _requestingOtp = false);
      }
    }
  }

  void _startRetryCountdown(int seconds) {
    _retryTimer?.cancel();
    setState(() => _retryAfterSeconds = seconds);
    if (seconds <= 0) return;
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryAfterSeconds <= 1) {
        timer.cancel();
        setState(() => _retryAfterSeconds = 0);
      } else {
        setState(() => _retryAfterSeconds -= 1);
      }
    });
  }

  Future<void> _verifyOtp(String code) async {
    final requestedPhone = _requestedPhone;
    if (requestedPhone == null || _verifyingOtp) return;
    setState(() => _verifyingOtp = true);
    _showBlockingProgress('Numara doğrulanıyor...');

    try {
      final result = await AuthApi.verifyOtp(phone: requestedPhone, code: code);
      await result.session.save();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      widget.onAuthenticated(result.session);
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _otpController.clear();
      await _showErrorDialog(_friendlyError(error.toString()));
      _otpFocusNode.requestFocus();
    } finally {
      if (mounted) {
        setState(() => _verifyingOtp = false);
      }
    }
  }

  Future<void> _showResendSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Kodu almadınız mı?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: Text(
                  _retryAfterSeconds > 0
                      ? 'SMS’i tekrar gönder ($_retryAfterSeconds sn)'
                      : 'SMS’i tekrar gönder',
                ),
                enabled: _retryAfterSeconds == 0 && !_requestingOtp,
                onTap: _retryAfterSeconds > 0 || _requestingOtp
                    ? null
                    : () => Navigator.of(context).pop('resend'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Numarayı düzenle'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'resend') {
      await _requestOtp();
      return;
    }
    if (action == 'edit') {
      setState(() {
        _step = _TurnaAuthStep.phone;
        _otpController.clear();
      });
    }
  }

  Future<void> _showErrorDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('İşlem başarısız'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  void _showBlockingProgress(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 18),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  String _friendlyError(String raw) {
    final text = raw.replaceFirst('Exception: ', '').trim();
    if (text.contains('Kod hatalı')) {
      return 'Kod hatalı, yeniden dene.';
    }
    if (text.contains('Lütfen biraz bekleyip tekrar dene')) {
      return text;
    }
    if (text.contains('Doğrulama şu an kullanılamıyor')) {
      return text;
    }
    return text;
  }

  Widget _buildWelcomeStep() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_vert),
                ),
              ),
              const Spacer(),
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: TurnaColors.primary50,
                  borderRadius: BorderRadius.circular(42),
                ),
                padding: const EdgeInsets.all(22),
                child: Image.asset('assets/turna-icon.png', fit: BoxFit.cover),
              ),
              const SizedBox(height: 48),
              const Text(
                "Turna'ya Hoş Geldiniz",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF202124),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Aileniz, arkadaşlarınız ve hizmetlerinizle güvenli şekilde iletişim kurmak için telefon numaranızı doğrulamanız gerekir.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {},
                child: const Text('Daha fazla bilgi'),
              ),
              const SizedBox(height: 12),
              const Text.rich(
                TextSpan(
                  text:
                      'Gizlilik İlkemizi okuyun. Hizmet Koşullarını kabul etmek için ',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF6B7280),
                  ),
                  children: [
                    TextSpan(
                      text: '"Kabul et ve devam et"',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' düğmesine dokunun.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4F6),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Türkçe',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: TurnaColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () => setState(() => _step = _TurnaAuthStep.phone),
                  child: const Text('Kabul et ve devam et'),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    final countryLabel = _selectedCountry?.name ?? 'Geçersiz ülke';
    final isInvalidCountry = _selectedCountry == null;
    final formWidth = math.min(MediaQuery.of(context).size.width - 56, 286.0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: const [
          SizedBox(width: 12),
          Icon(Icons.more_vert),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 14, 28, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      SizedBox(
                        width: formWidth,
                        child: const Text(
                          'Telefon numaranızı girin',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF202124),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: formWidth,
                        child: const Text.rich(
                          TextSpan(
                            text:
                                "Turna'nın telefon numaranızı doğrulaması gerekecek. Operatörünüz tarafından ücret uygulanabilir. ",
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Color(0xFF6B7280),
                            ),
                            children: [
                              TextSpan(
                                text: 'Numaram nedir?',
                                style: TextStyle(
                                  color: TurnaColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: formWidth,
                        child: InkWell(
                          onTap: _pickCountry,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        countryLabel,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: isInvalidCountry
                                              ? TurnaColors.error
                                              : const Color(0xFF202124),
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      color: TurnaColors.primary,
                                      size: 20,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 1.2,
                                  color: TurnaColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: formWidth,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 74,
                              child: TextField(
                                controller: _dialCodeController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  prefixText: '+',
                                  hintText: '90',
                                  isDense: true,
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: TurnaColors.primary,
                                      width: 1.2,
                                    ),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: TurnaColors.primary,
                                      width: 1.6,
                                    ),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextField(
                                controller: _nationalNumberController,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  hintText: 'Telefon numarası',
                                  isDense: true,
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: TurnaColors.primary,
                                      width: 1.2,
                                    ),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: TurnaColors.primary,
                                      width: 1.6,
                                    ),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 18),
                                onSubmitted: (_) => _confirmPhone(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _canContinuePhoneStep
                                ? TurnaColors.primary
                                : const Color(0xFFE9ECEF),
                            foregroundColor: _canContinuePhoneStep
                                ? Colors.white
                                : const Color(0xFF9AA1A9),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: _canContinuePhoneStep
                              ? _confirmPhone
                              : null,
                          child: const Text('İleri'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text.rich(
                        TextSpan(
                          text: 'Kaydolmak için ',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Color(0xFF6B7280),
                          ),
                          children: [
                            TextSpan(
                              text: 'en az 13 yaşında',
                              style: TextStyle(
                                color: TurnaColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' olmanız gerekir. Turna’nın '),
                            TextSpan(
                              text: 'WOW GLOBAL',
                              style: TextStyle(
                                color: TurnaColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' ile nasıl çalıştığını öğrenin.'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpStep() {
    final phone = _requestedPhone ?? '';
    final otpWidth = math.min(MediaQuery.of(context).size.width - 56, 286.0);
    final formattedPhone =
        _selectedCountry != null && _nationalNumber.isNotEmpty
        ? _formatPhonePreview(
            countryIso: _selectedCountry!.iso,
            dialCode: _selectedCountry!.dialCode,
            nationalNumber: _nationalNumber,
          )
        : phone;
    final digits = _otpController.text.padRight(6);
    final filledCount = _otpController.text.length.clamp(0, 6);
    const cellWidth = 16.0;
    const cellGap = 8.0;
    const cellCount = 6;
    const indicatorWidth =
        (cellWidth * cellCount) + (cellGap * (cellCount - 1));
    final cursorLeft = ((indicatorWidth - 2) / cellCount) * filledCount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: const [Icon(Icons.more_vert), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
          children: [
            Center(
              child: SizedBox(
                width: otpWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Numaranız doğrulanıyor',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF202124),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(
                        text:
                            '$formattedPhone numaralı telefona SMS yoluyla gönderilen 6 haneli kodu otomatik olarak algılaması bekleniyor. ',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Color(0xFF6B7280),
                        ),
                        children: [
                          TextSpan(
                            text: 'Numara yanlış mı?',
                            style: const TextStyle(
                              color: TurnaColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                setState(() {
                                  _step = _TurnaAuthStep.phone;
                                  _otpController.clear();
                                });
                              },
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    GestureDetector(
                      onTap: () => _otpFocusNode.requestFocus(),
                      child: SizedBox(
                        width: indicatorWidth,
                        height: 56,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Opacity(
                                opacity: 0.02,
                                child: TextField(
                                  controller: _otpController,
                                  focusNode: _otpFocusNode,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode,
                                  ],
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    counterText: '',
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 7,
                              child: Container(
                                height: 1.2,
                                color: const Color(0xFFC8CDD1),
                              ),
                            ),
                            if (filledCount < 6)
                              Positioned(
                                left: cursorLeft,
                                top: 4,
                                child: Container(
                                  width: 2,
                                  height: 28,
                                  color: const Color(0xFF2E7D5B),
                                ),
                              ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(cellCount, (index) {
                                  final char = digits[index].trim();
                                  return SizedBox(
                                    width: cellWidth,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: index == cellCount - 1
                                            ? 0
                                            : cellGap,
                                      ),
                                      child: Text(
                                        char.isEmpty ? '—' : char,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w500,
                                          color: char.isEmpty
                                              ? const Color(0xFF5F6368)
                                              : const Color(0xFF202124),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextButton(
                      onPressed: _showResendSheet,
                      child: const Text('Kodu almadınız mı?'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _TurnaAuthStep.welcome => _buildWelcomeStep(),
      _TurnaAuthStep.phone => _buildPhoneStep(),
      _TurnaAuthStep.otp => _buildOtpStep(),
    };
  }
}

class _TurnaCountryPickerSheet extends StatefulWidget {
  const _TurnaCountryPickerSheet();

  @override
  State<_TurnaCountryPickerSheet> createState() =>
      _TurnaCountryPickerSheetState();
}

class _TurnaCountryPickerSheetState extends State<_TurnaCountryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refresh);
  }

  @override
  void dispose() {
    _searchController.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final items = _kTurnaCountries.where((item) {
      if (query.isEmpty) return true;
      return item.name.toLowerCase().contains(query) ||
          item.iso.toLowerCase().contains(query) ||
          item.dialCode.contains(query);
    }).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 520,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DBE0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Ulke ara',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFFF3F5F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 20, endIndent: 20),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item.name),
                      trailing: Text(
                        item.dialCode,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () => Navigator.of(context).pop(item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TurnaProfileOnboardingPage extends StatefulWidget {
  const TurnaProfileOnboardingPage({
    super.key,
    required this.session,
    required this.onCompleted,
  });

  final AuthSession session;
  final void Function(AuthSession session) onCompleted;

  @override
  State<TurnaProfileOnboardingPage> createState() =>
      _TurnaProfileOnboardingPageState();
}

class _TurnaProfileOnboardingPageState
    extends State<TurnaProfileOnboardingPage> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _aboutController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _avatarBusy = false;
  bool _saving = false;
  String? _avatarUrlOverride;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!_looksGeneratedDisplayName(widget.session.displayName)) {
      _displayNameController.text = widget.session.displayName;
    }
    _usernameController.text =
        widget.session.username ??
        _buildUsernameSuggestion(_displayNameController.text);
    _displayNameController.addListener(_refresh);
    _displayNameController.addListener(_syncUsernameSuggestion);
    _usernameController.addListener(_refresh);
    _aboutController.addListener(_refresh);
  }

  @override
  void dispose() {
    _displayNameController.removeListener(_refresh);
    _displayNameController.removeListener(_syncUsernameSuggestion);
    _usernameController.removeListener(_refresh);
    _aboutController.removeListener(_refresh);
    _displayNameController.dispose();
    _usernameController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _displayNameController.text.trim().length >= 3 &&
      _usernameController.text.trim().length >= 3;

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _looksGeneratedDisplayName(String value) {
    return RegExp(r'^user_\d+$').hasMatch(value.trim().toLowerCase());
  }

  String _buildUsernameSuggestion(String raw) {
    final fallbackDigits = (widget.session.phone ?? '')
        .replaceAll(RegExp(r'\D+'), '')
        .characters
        .takeLast(4)
        .toString();
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r'[^a-z0-9._]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    var candidate = normalized;
    if (candidate.isEmpty) {
      candidate = 'turna${fallbackDigits.isEmpty ? '001' : fallbackDigits}';
    }
    if (!RegExp(r'^[a-z]').hasMatch(candidate)) {
      candidate = 'u_$candidate';
    }
    if (candidate.length < 3) {
      candidate = '${candidate}turna'.substring(0, 3);
    }
    return candidate.length > 24 ? candidate.substring(0, 24) : candidate;
  }

  void _syncUsernameSuggestion() {
    if (_usernameController.text.trim().isNotEmpty) return;
    final suggestion = _buildUsernameSuggestion(_displayNameController.text);
    _usernameController.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  String? _guessImageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return null;
  }

  Future<void> _pickAvatar() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1400,
    );
    if (file == null) return;

    final contentType = _guessImageContentType(file.name);
    if (contentType == null) {
      setState(() => _error = 'Desteklenmeyen gorsel formati.');
      return;
    }

    setState(() {
      _avatarBusy = true;
      _error = null;
    });

    try {
      final upload = await ProfileApi.createAvatarUpload(
        widget.session,
        contentType: contentType,
        fileName: file.name,
      );

      final bytes = await file.readAsBytes();
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Profil resmi yüklenemedi.');
      }

      final updatedProfile = await ProfileApi.completeAvatarUpload(
        widget.session,
        objectKey: upload.objectKey,
      );
      if (!mounted) return;
      setState(() {
        _avatarUrlOverride = updatedProfile.avatarUrl;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _completeOnboarding() async {
    if (!_canContinue || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updatedProfile = await ProfileApi.completeOnboarding(
        widget.session,
        displayName: _displayNameController.text.trim(),
        username: _usernameController.text.trim(),
        about: _aboutController.text,
      );

      final updatedSession = widget.session.copyWith(
        displayName: updatedProfile.displayName,
        username: updatedProfile.username,
        phone: updatedProfile.phone,
        avatarUrl: updatedProfile.avatarUrl,
        clearAvatarUrl: updatedProfile.avatarUrl == null,
        needsOnboarding: false,
      );
      await updatedSession.save();
      if (!mounted) return;
      widget.onCompleted(updatedSession);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
      return;
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = resolveTurnaSessionAvatarUrl(
      widget.session,
      overrideAvatarUrl: _avatarUrlOverride,
    );
    final label = _displayNameController.text.trim().isEmpty
        ? 'Profil'
        : _displayNameController.text.trim();

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            const Text(
              'Profilini tamamla',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: TurnaColors.text,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Karsindakiler profil resmini, adini ve biyografini burada gorecek.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: TurnaColors.textMuted,
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: GestureDetector(
                onTap: avatarUrl == null || avatarUrl.trim().isEmpty
                    ? null
                    : () => _openAvatarViewer(
                        context,
                        imageUrl: avatarUrl,
                        title: label,
                        token: widget.session.token,
                      ),
                child: _ProfileAvatar(
                  label: label,
                  avatarUrl: avatarUrl,
                  authToken: widget.session.token,
                  radius: 58,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: FilledButton.icon(
                onPressed: _avatarBusy || _saving ? null : _pickAvatar,
                icon: _avatarBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(
                  _avatarBusy ? 'Yukleniyor...' : 'Profil resmi ekle',
                ),
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _displayNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Ad',
                hintText: 'En az 3 karakter',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._@]')),
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final normalized = newValue.text
                      .toLowerCase()
                      .replaceAll('@', '')
                      .replaceAll(RegExp(r'[^a-z0-9._]+'), '');
                  return TextEditingValue(
                    text: normalized,
                    selection: TextSelection.collapsed(
                      offset: normalized.length,
                    ),
                  );
                }),
              ],
              decoration: const InputDecoration(
                labelText: 'Kullanıcı adı',
                hintText: 'ornek_kullanici',
                prefixText: '@',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _aboutController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Biyografi',
                hintText: 'Istersen kendinden kisa bir sey yaz',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!.replaceFirst('Exception: ', ''),
                  style: const TextStyle(color: TurnaColors.error),
                ),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              onPressed: _canContinue && !_saving ? _completeOnboarding : null,
              child: Text(_saving ? 'Devam ediliyor...' : 'Devam'),
            ),
          ],
        ),
      ),
    );
  }
}
