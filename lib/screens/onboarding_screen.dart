import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../widgets/dopa_card.dart';

/// Pantalla de bienvenida inicial de DOPA.
///
/// Pide el nombre personalizado de la persona (sin datos demo ni nombres fijos)
/// y permite opcionalmente conectar la URL de Docker + crear/iniciar sesión
/// en PostgreSQL desde el primer instante.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onCompleted;

  const OnboardingScreen({super.key, this.onCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _showServerSetup = false;
  bool _isLoginMode = false;
  bool _testingConnection = false;
  bool _submitting = false;
  bool? _serverReachable;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existingName = DBService.instance.usuarioActualCache.nombre.trim();
    if (existingName.isNotEmpty) {
      _nameController.text = existingName;
    }
    _urlController.text = ApiService.instance.baseUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testServerUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _serverReachable = false;
        _errorMessage = 'Escribe la URL de tu backend Docker o túnel HTTPS.';
        _statusMessage = null;
      });
      return;
    }

    setState(() {
      _testingConnection = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    final ok = await ApiService.instance.testAndSaveServer(url);
    if (!mounted) return;

    setState(() {
      _testingConnection = false;
      _serverReachable = ok;
      if (ok) {
        _statusMessage =
            'Servidor conectado en ${ApiService.instance.serverRootUrl}. Puedes crear tu cuenta o iniciar sesión abajo.';
        _errorMessage = null;
      } else {
        _errorMessage = ApiService.instance.lastHealthError ??
            'No se pudo contactar al servidor. Puedes empezar ahora en modo local y conectarlo luego.';
        _statusMessage = null;
      }
    });
  }

  Future<void> _continueToApp() async {
    final cleanName = _nameController.text.trim();
    if (!_isLoginMode && cleanName.isEmpty) {
      setState(() {
        _errorMessage = 'Por favor escribe tu nombre para personalizar DOPA.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final wantServerAccount = _showServerSetup &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;

    if (wantServerAccount) {
      try {
        final rawUrl = _urlController.text.trim();
        if (rawUrl.isNotEmpty) {
          final reachable = await ApiService.instance.testAndSaveServer(rawUrl);
          if (!reachable) {
            if (!mounted) return;
            setState(() {
              _submitting = false;
              _serverReachable = false;
              _errorMessage = ApiService.instance.lastHealthError ??
                  'El servidor no respondió. Revisa la URL o continúa sin cuenta por ahora.';
            });
            return;
          }
        }

        if (_isLoginMode) {
          final authRes = await ApiService.instance.login(
            correo: _emailController.text.trim(),
            contrasena: _passwordController.text,
          );
          final serverUser = authRes['usuario'] as Map<String, dynamic>?;
          final serverName = (serverUser?['nombre'] as String?)?.trim() ?? '';
          final resolvedName =
              cleanName.isNotEmpty ? cleanName : serverName;
          if (resolvedName.isNotEmpty) {
            await DBService.instance.setUserName(resolvedName);
          }
        } else {
          await ApiService.instance.register(
            nombre: cleanName,
            correo: _emailController.text.trim(),
            contrasena: _passwordController.text,
          );
          await DBService.instance.setUserName(cleanName);
        }

        await DBService.instance.syncLocalDataToServer();
        DBService.instance.profileReadyNotifier.value = true;
        if (!mounted) return;
        widget.onCompleted?.call();
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _errorMessage = e is DopaApiException
              ? e.message
              : 'No se pudo completar el acceso: $e';
        });
        return;
      }
    }

    await DBService.instance.setUserName(cleanName);
    DBService.instance.profileReadyNotifier.value = true;
    if (!mounted) return;
    setState(() => _submitting = false);
    widget.onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: AppTheme.pastelMint,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: AppTheme.borderDark,
                        width: 2.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: AppTheme.borderDark,
                          offset: Offset(3, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/icon/dopa_logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Bienvenido a DOPA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tu espacio tranquilo empieza en blanco: tus tareas, tu ritmo y tu dopamina se construyen contigo desde cero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                DopaCard(
                  backgroundColor: AppTheme.surfaceWhite,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '¿Cómo te llamas?',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Lo usaremos para saludarte y personalizar tu asistente.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('onboarding_name_field'),
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _continueToApp(),
                        decoration: InputDecoration(
                          hintText: 'Ej. Camila, Mateo, Sofía...',
                          filled: true,
                          fillColor: AppTheme.background,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppTheme.borderDark,
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppTheme.borderDark,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                DopaCard(
                  backgroundColor: AppTheme.pastelYellow,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _showServerSetup = !_showServerSetup),
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cloud_outlined,
                              size: 20,
                              color: AppTheme.textPrimary,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Conectar con Docker / Cuenta ahora (opcional)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Icon(
                              _showServerSetup
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: AppTheme.textPrimary,
                            ),
                          ],
                        ),
                      ),
                      if (_showServerSetup) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'URL del servidor (túnel HTTPS o IP local):',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('onboarding_url_field'),
                                controller: _urlController,
                                keyboardType: TextInputType.url,
                                decoration: InputDecoration(
                                  hintText: 'https://tu-tunel.trycloudflare.com',
                                  filled: true,
                                  fillColor: AppTheme.surfaceWhite,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppTheme.borderDark,
                                      width: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed:
                                  _testingConnection ? null : _testServerUrl,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.pastelBlue,
                                foregroundColor: AppTheme.textPrimary,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: AppTheme.borderDark,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              child: _testingConnection
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Probar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Crear cuenta'),
                              selected: !_isLoginMode,
                              onSelected: (_) =>
                                  setState(() => _isLoginMode = false),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Ya tengo cuenta'),
                              selected: _isLoginMode,
                              onSelected: (_) =>
                                  setState(() => _isLoginMode = true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'Correo electrónico',
                            filled: true,
                            fillColor: AppTheme.surfaceWhite,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppTheme.borderDark,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Contraseña (mín. 8 caracteres)',
                            filled: true,
                            fillColor: AppTheme.surfaceWhite,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppTheme.borderDark,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelMint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.borderDark,
                        width: 1.3,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _serverReachable == true
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                          size: 18,
                          color: AppTheme.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelPeach,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.borderDark,
                        width: 1.3,
                      ),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ElevatedButton(
                  key: const Key('onboarding_submit_button'),
                  onPressed: _submitting ? null : _continueToApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.pastelMint,
                    foregroundColor: AppTheme.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(
                        color: AppTheme.borderDark,
                        width: 2,
                      ),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Text(
                          _showServerSetup &&
                                  _emailController.text.trim().isNotEmpty
                              ? (_isLoginMode
                                  ? 'Iniciar sesión y empezar'
                                  : 'Crear cuenta y empezar')
                              : 'Empezar ahora',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
