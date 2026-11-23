import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import 'dopa_card.dart';

/// Bottom sheet para configurar la conexión al servidor Docker (IP LAN)
/// y gestionar la cuenta de usuario autenticada en PostgreSQL.
class ServerSettingsSheet extends StatefulWidget {
  const ServerSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ServerSettingsSheet(),
    );
  }

  @override
  State<ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends State<ServerSettingsSheet> {
  late final TextEditingController _urlController;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isTestingConnection = false;
  bool _isSubmittingAuth = false;
  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: ApiService.instance.serverRootUrl,
    );
    final currentEmail = ApiService.instance.currentUser?['correo'] as String?;
    if (currentEmail != null && currentEmail.isNotEmpty) {
      _emailController.text = currentEmail;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _probarYGuardarServidor() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Escribe la IP o URL de tu servidor Docker (ej. http://192.168.1.10:8000).';
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _statusMessage = null;
    });

    await ApiService.instance.saveBaseUrl(rawUrl);

    try {
      final health = await ApiService.instance.checkHealth();
      // Sincroniza automáticamente una sesión válida si todavía no hay sesión activa
      await ApiService.instance.ensureAuthenticated();
      DBService.instance.resetCacheForSessionChange();
      await DBService.instance.getUsuario();
      await DBService.instance.obtenerTareas();
      if (!mounted) return;
      setState(() {
        _isTestingConnection = false;
        _statusIsError = false;
        _statusMessage =
            'Conectado correctamente (${health['service'] ?? 'DOPA API'}). Tus cambios se guardan en PostgreSQL.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTestingConnection = false;
        _statusIsError = true;
        _statusMessage =
            'No se pudo conectar a ${ApiService.instance.serverRootUrl}. Verifica que Docker esté corriendo y ambos dispositivos estén en el mismo Wi-Fi.';
      });
    }
  }

  Future<void> _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (_isRegisterMode && name.isEmpty)) {
      setState(() {
        _statusIsError = true;
        _statusMessage = _isRegisterMode
            ? 'Completa tu nombre, correo y contraseña (mín. 8 caracteres).'
            : 'Ingresa tu correo y contraseña para continuar.';
      });
      return;
    }

    setState(() {
      _isSubmittingAuth = true;
      _statusMessage = null;
    });

    try {
      if (_isRegisterMode) {
        await ApiService.instance.register(
          nombre: name,
          correo: email,
          contrasena: password,
        );
      } else {
        await ApiService.instance.login(
          correo: email,
          contrasena: password,
        );
      }
      DBService.instance.resetCacheForSessionChange();
      await DBService.instance.getUsuario();
      await DBService.instance.obtenerTareas();
      if (!mounted) return;
      setState(() {
        _isSubmittingAuth = false;
        _statusIsError = false;
        _statusMessage = _isRegisterMode
            ? '¡Cuenta creada y conectada a PostgreSQL!'
            : '¡Sesión iniciada correctamente!';
      });
    } on DopaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmittingAuth = false;
        _statusIsError = true;
        _statusMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmittingAuth = false;
        _statusIsError = true;
        _statusMessage =
            'Sin respuesta del servidor ${ApiService.instance.serverRootUrl}. Revisa la IP de Docker.';
      });
    }
  }

  Future<void> _cerrarSesion() async {
    await ApiService.instance.logout();
    DBService.instance.resetCacheForSessionChange();
    if (!mounted) return;
    setState(() {
      _passwordController.clear();
      _statusIsError = false;
      _statusMessage = 'Sesión cerrada. Puedes iniciar con otra cuenta o crear una nueva.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final currentUser = ApiService.instance.currentUser;
    final userName = (currentUser?['nombre'] as String?) ??
        DBService.instance.usuarioActualCache.nombre;
    final userEmail = (currentUser?['correo'] as String?) ??
        DBService.instance.usuarioActualCache.correo;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppTheme.borderDark, width: 2),
          left: BorderSide(color: AppTheme.borderDark, width: 2),
          right: BorderSide(color: AppTheme.borderDark, width: 2),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle superior
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.borderDark.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Título y cerrar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Conexión Docker y Cuenta',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: AppTheme.borderDark),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Indicador de estado en vivo
              ValueListenableBuilder<bool>(
                valueListenable: ApiService.instance.connectionStatusNotifier,
                builder: (context, isOnline, _) {
                  return DopaCard(
                    backgroundColor:
                        isOnline ? AppTheme.pastelMint : AppTheme.pastelPeach,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    borderRadius: AppTheme.radiusMedium,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? const Color(0xFF2E9D68)
                                : const Color(0xFFD96B43),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isOnline
                                ? 'Conectado a Docker · ${ApiService.instance.serverRootUrl}'
                                : 'Sin conexión a Docker (${ApiService.instance.serverRootUrl})',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              if (_statusMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusIsError
                        ? AppTheme.pastelPink
                        : AppTheme.pastelLime,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderDark, width: 1.4),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ===============================================================
              // SECCIÓN 1: URL DEL SERVIDOR DOCKER
              // ===============================================================
              Text(
                '1. Servidor Backend (Docker)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ingresa la URL pública HTTPS de tu túnel Docker (para usar con datos/Internet, ej. https://xxx.trycloudflare.com) o tu IP Wi-Fi local (ej. http://192.168.1.25:8000).',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://tu-tunel.trycloudflare.com',
                  filled: true,
                  fillColor: AppTheme.surfaceWhite,
                  prefixIcon: const Icon(Icons.dns_outlined, color: AppTheme.borderDark),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.borderDark, width: 1.6),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.borderDark, width: 1.6),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.borderDark, width: 2.2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DopaCard(
                backgroundColor: AppTheme.pastelBlue,
                padding: const EdgeInsets.symmetric(vertical: 13),
                borderRadius: AppTheme.radiusMedium,
                onTap: _isTestingConnection ? null : _probarYGuardarServidor,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isTestingConnection)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppTheme.borderDark,
                        ),
                      )
                    else
                      const Icon(Icons.wifi_tethering_rounded, color: AppTheme.borderDark, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _isTestingConnection
                            ? 'Probando conexión...'
                            : 'Probar y guardar servidor',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ===============================================================
              // SECCIÓN 2: CUENTA DE USUARIO EN POSTGRESQL
              // ===============================================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '2. Tu cuenta DOPA',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (ApiService.instance.isAuthenticated)
                    TextButton(
                      onPressed: _cerrarSesion,
                      child: const Text(
                        'Cerrar sesión',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              if (ApiService.instance.isAuthenticated) ...[
                DopaCard(
                  backgroundColor: AppTheme.surfaceWhite,
                  padding: const EdgeInsets.all(12),
                  borderRadius: AppTheme.radiusMedium,
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.pastelYellow,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.borderDark, width: 1.5),
                        ),
                        child: const Icon(Icons.person_outline, color: AppTheme.borderDark),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              userEmail,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Selector Iniciar sesión / Crear cuenta
              Container(
                height: 40,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EDE8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _buildAuthModeTab('Iniciar sesión', false),
                    _buildAuthModeTab('Crear cuenta', true),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_isRegisterMode) ...[
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDecoration('Tu nombre', Icons.badge_outlined),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('Correo (ej. tu@correo.com)', Icons.email_outlined),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _inputDecoration('Contraseña (mín. 8 caracteres)', Icons.lock_outline)
                    .copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              DopaCard(
                backgroundColor: AppTheme.pastelLime,
                padding: const EdgeInsets.symmetric(vertical: 13),
                borderRadius: AppTheme.radiusMedium,
                onTap: _isSubmittingAuth ? null : _submitAuth,
                child: Center(
                  child: _isSubmittingAuth
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppTheme.borderDark,
                          ),
                        )
                      : Text(
                          _isRegisterMode
                              ? 'Crear cuenta y entrar'
                              : 'Iniciar sesión',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthModeTab(String label, bool isRegister) {
    final selected = _isRegisterMode == isRegister;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _isRegisterMode = isRegister;
          _statusMessage = null;
        }),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? AppTheme.surfaceWhite : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppTheme.surfaceWhite,
      prefixIcon: Icon(icon, color: AppTheme.borderDark),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.borderDark, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.borderDark, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.borderDark, width: 2.2),
      ),
    );
  }
}
