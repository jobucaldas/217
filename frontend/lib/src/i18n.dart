import 'dates.dart';

/// UI languages. Without a saved choice the app follows the device language,
/// falling back to English.
enum AppLanguage { en, pt, es }

extension AppLanguageX on AppLanguage {
  String get id => name;

  /// Name shown in the language picker, always in its own language.
  String get nativeName => switch (this) {
        AppLanguage.en => 'English',
        AppLanguage.pt => 'Português',
        AppLanguage.es => 'Español',
      };

  /// `intl` locale for dates; all three are initialized in `main.dart`.
  String get dateLocale => switch (this) {
        AppLanguage.en => 'en_US',
        AppLanguage.pt => 'pt_BR',
        AppLanguage.es => 'es',
      };

  /// The language for an id or language code (`pt`, `es`…), or null.
  static AppLanguage? tryFromId(String? raw) {
    for (final language in AppLanguage.values) {
      if (language.id == raw) return language;
    }
    return null;
  }

  /// First supported language in [languageCodes] (device preference order),
  /// else English.
  static AppLanguage fromDevice(Iterable<String> languageCodes) {
    for (final code in languageCodes) {
      final language = tryFromId(code);
      if (language != null) return language;
    }
    return AppLanguage.en;
  }
}

class Strings {
  const Strings(this.language);

  final AppLanguage language;

  String _t(String en, String pt, String es) => switch (language) {
        AppLanguage.en => en,
        AppLanguage.pt => pt,
        AppLanguage.es => es,
      };

  String get dateLocale => language.dateLocale;

  /// Display date formats (month names capitalized).
  AppDates get dates => AppDates(dateLocale);

  /// Sunday-first weekday initials for the month grid.
  List<String> get weekdayInitials => switch (language) {
        AppLanguage.en => const ['S', 'M', 'T', 'W', 'T', 'F', 'S'],
        AppLanguage.pt => const ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'],
        AppLanguage.es => const ['D', 'L', 'M', 'X', 'J', 'V', 'S'],
      };

  String get brand => '217';
  String get continueWorkOS => _t('Sign in', 'Entrar', 'Iniciar sesión');

  /// WorkOS button label when the password form is shown too (two buttons
  /// must not carry the same label).
  String get continueWorkOSOther => _t(
      'Continue with WorkOS', 'Continuar com a WorkOS', 'Continuar con WorkOS');

  // Email + password sign-in (first-party sign-in)
  String get signInEmail => _t(
        'Sign in with email',
        'Entrar com e-mail',
        'Iniciar sesión con correo',
      );
  String get emailLabel => _t('Email', 'E-mail', 'Correo');
  String get passwordLabel =>
      _t('Password', 'Senha', 'Contraseña');
  String get passwordShow => _t('Show password', 'Mostrar senha', 'Mostrar contraseña');
  String get passwordHide => _t('Hide password', 'Ocultar senha', 'Ocultar contraseña');
  String get newPasswordLabel =>
      _t('New password', 'Nova senha', 'Nueva contraseña');
  String get currentPasswordLabel => _t(
        'Current password',
        'Senha atual',
        'Contraseña actual',
      );
  String get confirmPasswordLabel => _t(
        'Confirm password',
        'Confirmar senha',
        'Confirmar contraseña',
      );
  String get passwordPolicyHint => _t(
        '15-128 characters.',
        'De 15 a 128 caracteres.',
        'De 15 a 128 caracteres.',
      );
  String get orDivider => _t('or', 'ou', 'o');
  String get createAccount => _t(
        'Create account',
        'Criar conta',
        'Crear cuenta',
      );
  String get signInTitle => _t('Sign in', 'Entrar', 'Iniciar sesión');

  /// The server's minimum password length (backend passwordauth.MinPasswordLen).
  static const passwordMinChars = 15;
  String passwordTooShort(int min) => _t(
        'Use at least $min characters.',
        'Use pelo menos $min caracteres.',
        'Usa al menos $min caracteres.',
      );
  String get passwordMismatch => _t(
        "Passwords don't match.",
        'As senhas não coincidem.',
        'Las contraseñas no coinciden.',
      );
  String get invalidEmailOrPassword => _t(
        'Wrong email or password.',
        'E-mail ou senha incorretos.',
        'Correo o contraseña incorrectos.',
      );
  String get emailTaken => _t(
        'This email already has an account. Sign in instead.',
        'Este e-mail já tem uma conta. Entre em vez de criar.',
        'Este correo ya tiene una cuenta. Inicia sesión en su lugar.',
      );
  String rateLimited(int seconds) => _t(
        'Too many attempts. Try again in $seconds s.',
        'Muitas tentativas. Tente de novo em $seconds s.',
        'Demasiados intentos. Inténtalo en $seconds s.',
      );
  String get verifyEmailTitle => _t(
        'Check your email',
        'Confira seu e-mail',
        'Revisa tu correo',
      );
  String verifyEmailBody(String email) => _t(
        'We sent a code to $email. Enter it to finish.',
        'Enviamos um código para $email. Digite-o para concluir.',
        'Enviamos un código a $email. Introdúcelo para terminar.',
      );
  String get codeLabel => _t('Code', 'Código', 'Código');
  String get verify => _t('Verify', 'Verificar', 'Verificar');
  String get invalidCode => _t(
        'Invalid or expired code.',
        'Código inválido ou expirado.',
        'Código inválido o caducado.',
      );
  String get resendCode => _t('Resend code', 'Reenviar código', 'Reenviar código');
  String resendIn(int seconds) => _t(
        'Resend in ${seconds}s',
        'Reenviar em ${seconds}s',
        'Reenviar en ${seconds}s',
      );
  String get passwordSaved => _t(
        'Password saved.',
        'Senha salva.',
        'Contraseña guardada.',
      );
  String get passwordRemoved => _t(
        'Password removed.',
        'Senha removida.',
        'Contraseña eliminada.',
      );
  String get currentPasswordWrong => _t(
        'Current password is wrong.',
        'A senha atual está errada.',
        'La contraseña actual es incorrecta.',
      );
  String get removePasswordTitle => _t(
        'Remove password?',
        'Remover a senha?',
        '¿Eliminar la contraseña?',
      );
  String get removePasswordBody => _t(
        'You will no longer be able to sign in with a password.',
        'Você não poderá mais entrar com uma senha.',
        'Ya no podrás iniciar sesión con contraseña.',
      );
  String get removePasswordNeedsOther => _t(
        'Set up another sign-in method before removing the password.',
        'Configure outro método de login antes de remover a senha.',
        'Configura otro método de inicio de sesión antes de eliminar la contraseña.',
      );
  String get reauthNeeded => _t(
        'Sign in again to confirm it is you, then try here again.',
        'Entre de novo para confirmar que é você e tente aqui de novo.',
        'Inicia sesión de nuevo para confirmar que eres tú y vuelve a intentarlo.',
      );
  String get signInMethods => _t(
        'Sign-in methods',
        'Métodos de entrada',
        'Métodos de inicio de sesión',
      );
  String get setPassword => _t('Set password', 'Definir senha', 'Definir contraseña');
  String get changePassword => _t(
        'Change password',
        'Mudar senha',
        'Cambiar contraseña',
      );
  String get removePassword => _t(
        'Remove password',
        'Remover senha',
        'Eliminar contraseña',
      );
  String get signInSubtitle => _t(
        'Medication Calendar',
        'Calendário de Remédios',
        'Calendario de Medicamentos',
      );
  String get logout => _t('Log out', 'Sair', 'Cerrar sesión');
  String appVersionLabel(String version) => _t(
        'Version $version',
        'Versão $version',
        'Versión $version',
      );
  String get settings => _t('Settings', 'Ajustes', 'Ajustes');
  String get languageLabel => _t('Language', 'Idioma', 'Idioma');
  String get taken => _t('Taken', 'Tomada', 'Tomada');
  String get missed => _t('Missed', 'Perdida', 'Olvidada');
  String get unrecorded => _t('Open', 'Em aberto', 'Pendiente');
  String get notes => _t('Note', 'Nota', 'Nota');
  String get addNote => _t('Add note', 'Adicionar nota', 'Añadir nota');
  String get heartLabel => _t('Sex', 'Sexo', 'Sexo');
  String get save => _t('Save', 'Salvar', 'Guardar');
  String get cancel => _t('Cancel', 'Cancelar', 'Cancelar');
  String get loading => _t('Loading…', 'Carregando…', 'Cargando…');
  String get signInError => _t(
        'Sign-in failed. Try again.',
        'Não deu para entrar. Tente de novo.',
        'No se pudo iniciar sesión. Inténtalo de nuevo.',
      );

  // Self-hosted server (signed-out Settings only)
  String get testConnection =>
      _t('Test connection', 'Testar conexão', 'Probar conexión');
  String get serverUrl => _t(
        'Self-hosted server URL',
        'URL do servidor próprio',
        'URL del servidor propio',
      );
  String get serverUrlHelp => _t(
        'Only if you host your own 217 server. Leave empty to use the default server.',
        'Só para quem hospeda o próprio servidor 217. Deixe vazio para usar o servidor padrão.',
        'Solo si alojas tu propio servidor 217. Déjalo vacío para usar el servidor predeterminado.',
      );
  String get serverSaved =>
      _t('Server saved', 'Servidor salvo', 'Servidor guardado');
  String get serverReset => _t(
        'Using the default server',
        'Usando o servidor padrão',
        'Usando el servidor predeterminado',
      );
  String get serverInvalid => _t(
        'Enter a full address, e.g. https://217.example.com',
        'Use um endereço completo, ex.: https://217.exemplo.com',
        'Escribe una dirección completa, p. ej. https://217.ejemplo.com',
      );
  String get connectionOk => _t(
        'Found a 217 server',
        'Servidor 217 encontrado',
        'Servidor 217 encontrado',
      );
  String get connectionFail => _t(
        'No 217 server answered at that address',
        'Nenhum servidor 217 respondeu nesse endereço',
        'Ningún servidor 217 respondió en esa dirección',
      );
  String get serverUnreachable => _t(
        "Can't reach that address. Check it and your connection.",
        'Não deu para acessar esse endereço. Confira o endereço e a sua conexão.',
        'No se puede acceder a esa dirección. Revísala y revisa tu conexión.',
      );
  String get serverSignInOff => _t(
        "That server hasn't set up sign-in yet",
        'Esse servidor ainda não configurou o login',
        'Ese servidor aún no configuró el inicio de sesión',
      );
  String serverLabel(String host) =>
      _t('Server: $host', 'Servidor: $host', 'Servidor: $host');

  // Server setup (Android builds without a built-in server)
  String get serverSetupTitle => _t(
        'Connect to your server',
        'Conecte ao seu servidor',
        'Conéctate a tu servidor',
      );
  String get changeServerTitle =>
      _t('Change server', 'Trocar servidor', 'Cambiar servidor');
  String get serverSetupIntro => _t(
        "217 doesn't come with a server. Use one you run yourself, or one run by someone you trust.",
        'O 217 não vem com servidor. Use um que você mesmo mantém ou um mantido por alguém de confiança.',
        '217 no incluye un servidor. Usa uno que mantengas tú o uno de alguien de confianza.',
      );
  String get serverSetupBody => _t(
        "Enter the server's address, or paste an invite link you got.",
        'Digite o endereço do servidor ou cole um link de convite que você recebeu.',
        'Escribe la dirección del servidor o pega un enlace de invitación que recibiste.',
      );
  String get serverAddress =>
      _t('Server address', 'Endereço do servidor', 'Dirección del servidor');
  String get serverAddressHint =>
      _t('217.example.com', '217.exemplo.com', '217.ejemplo.com');
  String get serverAddressInvalid => _t(
        'Enter an address like 217.example.com',
        'Digite um endereço como 217.exemplo.com',
        'Escribe una dirección como 217.ejemplo.com',
      );
  String get serverNeedsHttps => _t(
        'The app only connects to https:// addresses',
        'O app só conecta a endereços https://',
        'La app solo se conecta a direcciones https://',
      );
  String get connect => _t('Connect', 'Conectar', 'Conectar');
  String get changeServerNote => _t(
        'Accounts belong to a server, so you sign in again after switching.',
        'Contas pertencem a um servidor, então você entra de novo depois de trocar.',
        'Las cuentas pertenecen a un servidor, así que vuelves a iniciar sesión al cambiar.',
      );
  String get selfHostGuide => _t('Self-hosting guide',
      'Guia de hospedagem própria', 'Guía para alojarlo tú');
  String get dismiss => _t('Dismiss', 'Dispensar', 'Descartar');
  String get showMore =>
      _t('Advanced options', 'Opções avançadas', 'Opciones avanzadas');
  String get showLess => _t(
        'Hide advanced options',
        'Ocultar opções avançadas',
        'Ocultar opciones avanzadas',
      );

  String get genericError => _t(
        'Something went wrong. Try again.',
        'Algo deu errado. Tente de novo.',
        'Algo salió mal. Inténtalo de nuevo.',
      );
  String get connectionError => _t(
        "Can't reach the server. Try again.",
        'Sem conexão com o servidor. Tente de novo.',
        'No se puede conectar con el servidor. Inténtalo de nuevo.',
      );
  String get retry => _t('Retry', 'Tentar de novo', 'Reintentar');
  String get syncOfflineTitle =>
      _t("You're offline", 'Você está sem conexão', 'Estás sin conexión');
  String get syncPendingTitle => _t('Changes waiting to sync',
      'Alterações aguardando envio', 'Cambios pendientes de enviar');
  String syncNoticeBody(bool offline, int pending) {
    final changes = _t(
      pending == 1 ? '1 change' : '$pending changes',
      pending == 1 ? '1 alteração' : '$pending alterações',
      pending == 1 ? '1 cambio' : '$pending cambios',
    );
    if (offline && pending == 0) {
      return _t(
          'Your calendar is saved on this phone. You stay signed in; it refreshes when the server is back.',
          'Seu calendário está salvo neste celular. Sua sessão continua ativa; ele atualiza quando o servidor voltar.',
          'Tu calendario está guardado en este teléfono. Sigues con la sesión iniciada; se actualiza cuando vuelva el servidor.');
    }
    if (offline) {
      return _t(
          '$changes saved on this phone. You stay signed in; they sync when the server is back.',
          '$changes salvas neste celular. Sua sessão continua ativa; elas serão enviadas quando o servidor voltar.',
          '$changes guardados en este teléfono. Sigues con la sesión iniciada; se enviarán cuando vuelva el servidor.');
    }
    return _t(
        '$changes saved on this phone, not yet on the server.',
        '$changes salvas neste celular, ainda não no servidor.',
        '$changes guardados en este teléfono, aún no en el servidor.');
  }

  String get syncNow => _t('Sync now', 'Enviar agora', 'Enviar ahora');
  String get done => _t('Done', 'Pronto', 'Listo');
  String get clearNote => _t('Clear note', 'Limpar nota', 'Borrar nota');
  String get appearance => _t('Appearance', 'Aparência', 'Apariencia');
  String get themeSystem => _t('System', 'Sistema', 'Sistema');
  String get themeLight => _t('Light', 'Claro', 'Claro');
  String get themeDark => _t('Dark', 'Escuro', 'Oscuro');
  String get colorTheme => _t('Accent', 'Cor de destaque', 'Color de acento');
  String get paletteBlue => _t('Blue', 'Azul', 'Azul');
  String get paletteCyan => _t('Cyan', 'Ciano', 'Cian');
  String get palettePurple => _t('Purple', 'Roxo', 'Morado');
  String get today => _t('Today', 'Hoje', 'Hoy');
  String get jumpToToday => _t('Jump to today', 'Ir para hoje', 'Ir a hoy');
  String get previousMonth =>
      _t('Previous month', 'Mês anterior', 'Mes anterior');
  String get nextMonth => _t('Next month', 'Próximo mês', 'Mes siguiente');
  String get recordToday =>
      _t('Record today', 'Registrar hoje', 'Registrar hoy');
  String get updateToday =>
      _t('Update today', 'Atualizar hoje', 'Actualizar hoy');
  String updateDay(String day) =>
      _t('Update $day', 'Atualizar $day', 'Actualizar $day');
  String get viewToday => _t('View today', 'Ver hoje', 'Ver hoy');
  String viewDay(String day) => _t('View $day', 'Ver $day', 'Ver $day');
  String get close => _t('Close', 'Fechar', 'Cerrar');

  // Reminders
  String get remindersOff =>
      _t('Reminder off', 'Lembrete desligado', 'Recordatorio desactivado');
  String get reminderNotReady => _t(
        'Reminder not set up yet',
        'Lembrete ainda não configurado',
        'Recordatorio aún no configurado',
      );
  String get reminderHint => _t(
        'Set a daily reminder in Settings > Reminder.',
        'Configure um lembrete diário em Ajustes > Lembrete.',
        'Configura un recordatorio diario en Ajustes > Recordatorio.',
      );
  String get reminderHintDismiss => _t('Got it', 'Entendi', 'Entendido');
  String get takenLabel => _t('Taken', 'Tomei', 'La tomé');
  String get missedLabel => _t('Missed', 'Perdi', 'La olvidé');
  String get reminders => _t('Reminder', 'Lembrete', 'Recordatorio');
  String get reminderTime => _t('Time', 'Horário', 'Hora');
  String get reminderEnable =>
      _t('Remind me daily', 'Lembrar todo dia', 'Recordarme cada día');
  String get remindersWithMessagesSubtitle => _t(
        'Daily pill reminder and messages',
        'Lembrete diário da pílula e mensagens',
        'Recordatorio diario de la píldora y mensajes',
      );
  String get reminderSaved => _t('Saved', 'Salvo', 'Guardado');
  String get reminderNeedsPush => _t(
        'Enable system notifications on this device.',
        'Ative as notificações do sistema neste aparelho.',
        'Activa las notificaciones del sistema en este dispositivo.',
      );
  String get reminderUnavailable => _t(
        "Reminders aren't available here yet. Use the Android app to get notifications.",
        'Lembretes ainda não estão disponíveis aqui. Use o app Android para receber notificações.',
        'Los recordatorios aún no están disponibles aquí. Usa la app de Android para recibir notificaciones.',
      );
  String get reminderReady =>
      _t('Reminder on', 'Lembrete ativo', 'Recordatorio activo');
  String get reminderNativeNote => _t(
        'On Android, the reminder is a daily notification on this device. In the browser, it depends on the server supporting push notifications.',
        'No Android, o lembrete é uma notificação diária neste aparelho. No navegador, depende do servidor ter notificações push.',
        'En Android, el recordatorio es una notificación diaria en este dispositivo. En el navegador, depende de que el servidor admita notificaciones push.',
      );
  String get reminderPermissionDenied => _t(
        'Notification permission denied on this device.',
        'Permissão de notificação negada neste aparelho.',
        'Permiso de notificaciones denegado en este dispositivo.',
      );
  String get reminderLocalScheduled => _t(
        'Local notification scheduled on this device',
        'Notificação local agendada neste aparelho',
        'Notificación local programada en este dispositivo',
      );
  String get reminderWebNeedsPush => _t(
        'In this browser, background reminders need push notifications from the server.',
        'Neste navegador, o lembrete em segundo plano precisa de notificações push do servidor.',
        'En este navegador, los recordatorios en segundo plano necesitan notificaciones push del servidor.',
      );
  String reminderRepeatHelper(int minutes) => _t(
        'Repeats every $minutes min until you log today’s pill, until the end of the day',
        'Repete a cada $minutes min até você registrar a pílula de hoje, até o fim do dia',
        'Se repite cada $minutes min hasta que registres la píldora de hoy, hasta el final del día',
      );

  // Updates (Android only)
  String get autoUpdateTitle => _t(
        'Check for updates',
        'Verificar atualizações',
        'Buscar actualizaciones',
      );
  String get updateAvailable => _t(
        'A new version is available',
        'Há uma versão nova disponível',
        'Hay una versión nueva disponible',
      );
  String get updateAction => _t('Update', 'Atualizar', 'Actualizar');

  // Account
  String get deleteAccount =>
      _t('Delete account', 'Excluir conta', 'Eliminar cuenta');
  String deleteAccountWarn(bool deletesLogin) => deletesLogin
      ? _t(
          'This permanently deletes your account and data and withdraws your consent. This cannot be undone.',
          'Isso apaga permanentemente sua conta e seus dados e revoga seu consentimento. Não dá para desfazer.',
          'Esto elimina permanentemente tu cuenta y tus datos y retira tu consentimiento. No se puede deshacer.',
        )
      : _t(
          'This permanently deletes your data on this server and withdraws your consent. This cannot be undone.',
          'Isso apaga permanentemente seus dados neste servidor e revoga seu consentimento. Não dá para desfazer.',
          'Esto elimina permanentemente tus datos en este servidor y retira tu consentimiento. No se puede deshacer.',
        );
  String get deleteAccountConfirm => _t('Delete', 'Excluir', 'Eliminar');
  String get accountDeleted =>
      _t('Account deleted', 'Conta excluída', 'Cuenta eliminada');

  // Sharing (owner side)
  String get shareCalendar => _t(
        'Share calendar with partner',
        'Compartilhar calendário com parceiro',
        'Compartir calendario con tu pareja',
      );
  String get shareInviteCode =>
      _t('Invite code', 'Código do convite', 'Código de invitación');
  String get shareInviteLink =>
      _t('Invite link', 'Link do convite', 'Enlace de invitación');
  String get shareSend =>
      _t('Send invite', 'Enviar convite', 'Enviar invitación');
  String get shareCopyCode => _t('Copy code', 'Copiar código', 'Copiar código');
  String get shareCopyLink => _t('Copy link', 'Copiar link', 'Copiar enlace');
  String get codeCopied =>
      _t('Code copied', 'Código copiado', 'Código copiado');
  String get linkCopied => _t('Link copied', 'Link copiado', 'Enlace copiado');
  String get shareSubject => _t(
        'Invite to my 217 calendar',
        'Convite para meu calendário 217',
        'Invitación a mi calendario 217',
      );

  /// Message handed to the system share sheet (WhatsApp, SMS…).
  String shareMessage({required String code, String link = ''}) {
    final codeLine = _t(
      'Open the 217 app and enter the code $code.',
      'Abra o app 217 e use o código $code.',
      'Abre la app 217 e introduce el código $code.',
    );
    if (link.isEmpty) {
      return _t(
        'Join my 217 calendar! $codeLine',
        'Entre no meu calendário 217! $codeLine',
        '¡Únete a mi calendario 217! $codeLine',
      );
    }
    return _t(
      'Join my 217 calendar: $link\nOr: $codeLine',
      'Entre no meu calendário 217: $link\nOu: $codeLine',
      'Únete a mi calendario 217: $link\nO: $codeLine',
    );
  }

  String get shareEnable =>
      _t('Create invite', 'Gerar convite', 'Crear invitación');
  String get shareRevoke =>
      _t('Revoke access', 'Revogar acesso', 'Revocar acceso');
  String get shareActiveWith =>
      _t('Shared with', 'Compartilhado com', 'Compartido con');
  String get shareWaiting => _t(
        'Waiting for partner to join with the link or code.',
        'Aguardando o parceiro entrar pelo link ou código.',
        'Esperando a que tu pareja se una con el enlace o el código.',
      );

  // Sharing (partner side)
  String get pendingInviteTitle => _t(
        'Join the shared calendar?',
        'Entrar no calendário compartilhado?',
        '¿Unirte al calendario compartido?',
      );
  String pendingInviteBody(String code) => _t(
        'You opened an invite (code $code). Joining makes this account show her calendar, read-only, instead of your own.',
        'Você abriu um convite (código $code). Ao entrar, esta conta passa a mostrar o calendário dela, só para leitura, em vez do seu.',
        'Abriste una invitación (código $code). Al unirte, esta cuenta mostrará su calendario, solo lectura, en lugar del tuyo.',
      );
  String get notNow => _t('Not now', 'Agora não', 'Ahora no');
  String get joinedCalendar => _t(
        'You joined the calendar',
        'Você entrou no calendário',
        'Te uniste al calendario',
      );
  String get inbox => _t('Messages', 'Mensagens', 'Mensajes');
  String get inboxEmpty => _t(
        'No messages yet.',
        'Nenhuma mensagem ainda.',
        'Aún no hay mensajes.',
      );
  String get messageHint =>
      _t('Write a message', 'Escreva uma mensagem', 'Escribe un mensaje');
  String get sendNote => _t('Send', 'Enviar', 'Enviar');
  String get messagesNeedPartner => _t(
        'Link a partner in Settings to send messages.',
        'Vincule um parceiro nos Ajustes para enviar mensagens.',
        'Vincula a tu pareja en Ajustes para enviar mensajes.',
      );
  String get messageFromMe => _t('You', 'Você', 'Tú');
  String get messageUnread => _t('New', 'Nova', 'Nuevo');
  String messageNotifTitle(String from) => _t(
        from.trim().isEmpty ? 'New message' : 'New message from $from',
        from.trim().isEmpty ? 'Nova mensagem' : 'Nova mensagem de $from',
        from.trim().isEmpty ? 'Nuevo mensaje' : 'Nuevo mensaje de $from',
      );
  String messageNotifManyBody(int count) => _t(
        '$count new messages',
        '$count mensagens novas',
        '$count mensajes nuevos',
      );
  String get messageNotifsTitle => _t(
        'Messages',
        'Mensagens',
        'Mensajes',
      );
  String get partnerRevokedTitle => _t(
        'You are not invited to her 217 calendar',
        'Você não está convidado ao calendário 217 dela',
        'No estás invitado a su calendario 217',
      );
  String get partnerRevokedBody => _t(
        'Add her code, or delete this account?',
        'Quer adicionar o código dela ou excluir esta conta?',
        '¿Quieres añadir su código o eliminar esta cuenta?',
      );
  String get enterInviteCode =>
      _t('Invite code', 'Código do convite', 'Código de invitación');
  String get inviteCodeRejected => _t(
        "That code didn't work. Check it and try again.",
        'Esse código não funcionou. Confira e tente de novo.',
        'Ese código no funcionó. Revísalo e inténtalo de nuevo.',
      );
  String get joinCalendar => _t('Join', 'Entrar', 'Unirse');
  String get partnerMode => _t(
        'Partner Mode',
        'Modo Parceiro',
        'Modo Pareja',
      );

  // Roles: owner (takes the pill) vs partner (follows her calendar)
  String get roleChoiceTitle => _t(
        'How will you use 217?',
        'Como você vai usar o 217?',
        '¿Cómo usarás 217?',
      );
  String get roleOwnerTitle =>
      _t('I take the pill', 'Eu tomo a pílula', 'Yo tomo la píldora');
  String get roleOwnerBody => _t(
        'Log your pills and period. Invite your partner to follow along.',
        'Registre a pílula e a menstruação. Convide seu parceiro para acompanhar.',
        'Registra la píldora y la regla. Invita a tu pareja a seguirlo.',
      );
  String get rolePartnerTitle =>
      _t("I'm the partner", 'Sou o parceiro', 'Soy la pareja');
  String get rolePartnerBody => _t(
        'Follow her calendar with an invite. Get PMS and missed-pill alerts.',
        'Acompanhe o calendário dela com um convite. Receba avisos de TPM e de pílula esquecida.',
        'Sigue su calendario con una invitación. Recibe avisos de SPM y de píldora olvidada.',
      );
  String get roleChangeLater => _t(
        'You can change this later while nothing is shared.',
        'Dá para mudar depois, enquanto nada estiver compartilhado.',
        'Puedes cambiarlo después mientras no haya nada compartido.',
      );
  String get switchToPartner => _t(
        "Switch to partner mode",
        'Mudar para modo parceiro',
        'Cambiar a modo pareja',
      );
  String get switchToOwner => _t(
        'I take the pill instead',
        'Na verdade, eu tomo a pílula',
        'En realidad, yo tomo la píldora',
      );
  String get switchToPartnerWarn => _t(
        "Your logged days stay saved but are hidden while you're in partner mode.",
        'Seus dias registrados continuam salvos, mas ficam ocultos no modo parceiro.',
        'Tus días registrados se guardan, pero se ocultan en modo pareja.',
      );
  String get switchRoleConfirm => _t('Switch', 'Mudar', 'Cambiar');
  String get roleLocked => _t(
        'Stop sharing the calendar before changing this.',
        'Pare de compartilhar o calendário antes de mudar isso.',
        'Deja de compartir el calendario antes de cambiar esto.',
      );
  String get partnerJoinTitle => _t(
        'Join her calendar',
        'Entre no calendário dela',
        'Únete a su calendario',
      );
  String get partnerJoinBody => _t(
        'Ask her for the invite link or code from her 217 settings.',
        'Peça a ela o link ou código de convite nos ajustes do 217.',
        'Pídele el enlace o código de invitación de sus ajustes de 217.',
      );

  // Cycle / PMS
  String get periodLabel => _t('Period', 'Menstruação', 'Regla');
  String get expectedPeriod =>
      _t('Expected period', 'Menstruação prevista', 'Regla prevista');
  String get expectedPms => _t('Expected PMS', 'TPM prevista', 'SPM previsto');
  String cyclePmsFrom(String pms) => _t(
        'Expected PMS from ~$pms',
        'TPM prevista a partir de ~$pms',
        'SPM previsto desde ~$pms',
      );
  String cycleExpectedPeriod(String period) => _t(
        'Expected period ~$period',
        'Menstruação prevista ~$period',
        'Regla prevista ~$period',
      );
  String get cyclePmsNow =>
      _t('Expected PMS now', 'TPM prevista agora', 'SPM previsto ahora');
  String get cyclePeriodNow => _t(
        'Expected period now',
        'Menstruação prevista agora',
        'Regla prevista ahora',
      );
  String get cycleHintOwner => _t(
        'Mark period days to see the expected PMS',
        'Marque os dias de menstruação para ver a TPM prevista',
        'Marca los días de regla para ver el SPM previsto',
      );
  // Day sheet: the partner's read-only day, and pulling the sheet up
  String get pillLabel => _t('Pill', 'Pílula', 'Píldora');
  String get pillNotLogged => unrecorded;
  String get pillNotDue =>
      _t('Not due yet', 'Ainda não chegou', 'Todavía no toca');
  String get dayLogged => _t('Logged', 'Registrado', 'Registrado');
  String get comingUp => _t('Coming up', 'Próximos dias', 'Próximamente');
  String get dayThisDay => _t('This day', 'Neste dia', 'Este día');
  String get dayExpected => _t('Expected', 'Prevista', 'Prevista');
  String cycleUntilDate(String date) =>
      _t('until ~$date', 'até ~$date', 'hasta ~$date');
  String get showMoreNote => _t(
        'Show the whole note',
        'Mostrar a nota inteira',
        'Mostrar la nota entera',
      );
  String get showLessNote => _t(
        'Show less of the note',
        'Mostrar menos da nota',
        'Mostrar menos de la nota',
      );
  String cycleFromDate(String date) =>
      _t('from ~$date', 'a partir de ~$date', 'desde ~$date');
  String get cycleNoPredictions => _t(
        'No expected period or PMS for now.',
        'Sem menstruação ou TPM prevista por enquanto.',
        'Sin regla ni SPM previstos por ahora.',
      );
  String get daySheetMore => _t('Show more', 'Mostrar mais', 'Mostrar más');
  String get daySheetLess => _t('Show less', 'Mostrar menos', 'Mostrar menos');
  String get dayTapToLog =>
      _t('Tap to log', 'Registrar', 'Registrar');
  String get editNote => _t('Edit note', 'Editar nota', 'Editar nota');
  String get daySheetFutureLocked => _t(
        'Future day: nothing to log yet',
        'Dia futuro: nada para registrar ainda',
        'Día futuro: aún no hay nada que registrar',
      );
  String cycleStageNote(String code) => switch (code) {
        'pms_suppressed_menopause' => _t(
            '217 counts no PMS because you told 217 you are in menopause.',
            'O 217 não conta TPM porque você informou ao 217 que está na menopausa.',
            '217 no cuenta el SPM porque le dijiste a 217 que estás en la menopausia.'),
        'pms_counted_perimenopause' => _t(
            'You told 217 you are in perimenopause. Cycles can still happen, so PMS is still counted.',
            'Você informou ao 217 que está na perimenopausa. Ciclos ainda podem ocorrer, então a TPM continua sendo contada.',
            'Le dijiste a 217 que estás en la perimenopausia. Aún puede haber ciclos, así que se sigue contando el SPM.'),
        'no_cycles' => _t(
            '217 predicts no periods or PMS because you told 217 you have no cycles.',
            'O 217 não prevê menstruação nem TPM porque você informou ao 217 que não tem ciclos.',
            '217 no prevé reglas ni SPM porque le dijiste a 217 que no tienes ciclos.'),
        _ => '',
      };
  String get reproductiveStage =>
      _t('Reproductive stage', 'Fase reprodutiva', 'Etapa reproductiva');
  String get stageCycling => _t('Cycling', 'Com ciclos', 'Con ciclos');
  String get stagePerimenopause =>
      _t('Perimenopause', 'Perimenopausa', 'Perimenopausia');
  String get stageMenopause => _t('Menopause', 'Menopausa', 'Menopausia');
  String get stageNoCycles =>
      _t("I don't have cycles", 'Não tenho ciclos', 'No tengo ciclos');
  String get stageSelfReport => _t(
      'This is what you told 217; it is not a diagnosis.',
      'Isto é o que você informou ao 217; não é um diagnóstico.',
      'Esto es lo que le dijiste a 217; no es un diagnóstico.');
  String stageLabel(String stage) => switch (stage) {
        'perimenopause' => stagePerimenopause,
        'menopause' => stageMenopause,
        'no_cycles' => stageNoCycles,
        _ => stageCycling,
      };

  // Personal section (Settings)
  String get personal => _t('Personal', 'Pessoal', 'Personal');
  String get displayName =>
      _t('Display name', 'Nome de exibição', 'Nombre visible');
  String get displayNameSaved => _t('Display name saved.',
      'Nome de exibição salvo.', 'Nombre visible guardado.');
  String get birthDate =>
      _t('Birth month', 'Mês de nascimento', 'Mes de nacimiento');
  String get birthDateHelp => _t(
      'Month and year are enough. Used only to suggest your reproductive stage.',
      'Mês e ano bastam. Usado só para sugerir sua fase reprodutiva.',
      'Mes y año bastan. Solo se usa para sugerir tu etapa reproductiva.');
  String get notSet => _t('Not set', 'Não informado', 'Sin indicar');
  String get month => _t('Month', 'Mês', 'Mes');
  String get year => _t('Year', 'Ano', 'Año');
  String get clear => _t('Clear', 'Limpar', 'Borrar');
  String stageSuggestionBody(String stage) => stage == 'menopause'
      ? _t('You might be at menopause', 'Você pode estar na menopausa',
          'Puede que estés en la menopausia')
      : _t('You might be in perimenopause', 'Você pode estar na perimenopausa',
          'Puede que estés en la perimenopausia');
  String get stageSuggestionUpdate => _t('Update', 'Atualizar', 'Actualizar');
  String get stageUpdated => _t('Updated successfully',
      'Atualizado com sucesso', 'Actualizado correctamente');
  String get pmsNotCounted => _t(
      'PMS is not counted for the stage you selected.',
      'A TPM não é contada na fase que você selecionou.',
      'El SPM no se cuenta en la etapa que seleccionaste.');

  // Partner alerts
  String get partnerAlerts =>
      _t('Notifications', 'Notificações', 'Notificaciones');
  String get pmsAlertTitle => _t(
        'PMS forecast',
        'Previsão de TPM',
        'Previsión de SPM',
      );
  String get pillAlertTitle => _t(
        'Medication Not Logged',
        'Remédio Não Registrado',
        'Medicamento No Registrado',
      );
  String get pillRepeatTitle => _t('Repeat', 'Repetir', 'Repetir');
  String get pillRepeatSubtitle => _t(
        'Repeat until the pill is logged',
        'Repetir até registrar a pílula',
        'Repetir hasta registrar la píldora',
      );
  String get pillRepeatEveryLabel => _t('Every', 'A cada', 'Cada');
  String get pillRepeatMinutesUnit => _t('minutes', 'minutos', 'minutos');
  String get pillRepeatRangeError => _t(
        'Enter 1 to 120 minutes',
        'Informe de 1 a 120 minutos',
        'Indica de 1 a 120 minutos',
      );
  String pillRepeatHelper(int minutes) => _t(
        'Repeats every $minutes min until you log the pill, through the end of the day',
        'Repete a cada $minutes min até você registrar a pílula, até o fim do dia',
        'Se repite cada $minutes min hasta que registres la píldora, hasta el final del día',
      );
  String get partnerAlertsNote => _t(
        'Notifications are scheduled on this phone from her latest calendar each time 217 syncs, so open it now and then.',
        'As notificações são agendadas neste celular com o calendário mais recente dela sempre que o 217 sincroniza, então abra o app de vez em quando.',
        'Las notificaciones se programan en este teléfono con su calendario más reciente cada vez que 217 se sincroniza, así que ábrelo de vez en cuando.',
      );
  String get partnerAlertsWeb => _t(
        'Notifications are delivered by the Android app.',
        'As notificações são entregues pelo app Android.',
        'Las notificaciones las entrega la app de Android.',
      );
  String get partnerAlertsNeedLink => _t(
        'Alerts start once you join her calendar.',
        'Os avisos começam quando você entrar no calendário dela.',
        'Los avisos empiezan cuando te unas a su calendario.',
      );
  String partnerName(String name) =>
      name.trim().isEmpty ? _t('She', 'Ela', 'Ella') : name.trim();
  String get pmsNotifTitle =>
      _t('Expected PMS', 'TPM prevista', 'SPM previsto');
  String pmsNotifBody(String name, String start, String end) => _t(
        '${partnerFirstName(name)}: expected between ~$start - $end',
        '${partnerFirstName(name)}: prevista entre ~$start - $end',
        '${partnerFirstName(name)}: previsto entre ~$start - $end',
      );
  String get pillNotifTitle => _t(
        'Medicine not taken',
        'Remédio não tomado',
        'Medicamento no tomado',
      );
  String pillNotifBody(String name, String time) => _t(
        '${partnerFirstName(name)}: not logged as of $time',
        '${partnerFirstName(name)}: sem registro às $time',
        '${partnerFirstName(name)}: sin registro a las $time',
      );
  String partnerFirstName(String name) =>
      partnerName(name).split(RegExp(r'\s+')).first;

  // Privacy (LGPD)
  String get privacyTitle => _t('Your data and privacy',
      'Seus dados e privacidade', 'Tus datos y privacidad');
  String get privacyNotice =>
      _t('Privacy notice', 'Aviso de privacidade', 'Aviso de privacidad');
  String get consentIntro => _t(
        '217 handles sensitive health data, so it needs your consent first. Read the privacy notice: it explains what is stored, why, and how to download or delete your data or withdraw consent later.',
        'O 217 trata dados sensíveis de saúde, por isso precisa do seu consentimento antes. Leia o aviso de privacidade: ele explica o que é guardado, para quê, e como baixar ou excluir seus dados ou revogar o consentimento depois.',
        '217 trata datos sensibles de salud, por eso necesita tu consentimiento primero. Lee el aviso de privacidad: explica qué se guarda, para qué y cómo descargar o eliminar tus datos o retirar el consentimiento después.',
      );
  String get consentAccept =>
      _t('I have read and accept', 'Li e aceito', 'He leído y acepto');
  String get consentNoticeChanged => _t(
        'The privacy notice was just updated. Read it again before accepting.',
        'O aviso de privacidade acabou de mudar. Leia de novo antes de aceitar.',
        'El aviso de privacidad acaba de cambiar. Léelo de nuevo antes de aceptar.',
      );
  String get sharedCalendarOwnerConsentRequired => _t(
        'The calendar owner must agree to the current privacy notice before you can view their calendar.',
        'A pessoa responsável pelo calendário precisa concordar com o aviso de privacidade atual antes que você possa vê-lo.',
        'La persona responsable del calendario debe aceptar el aviso de privacidad actual antes de que puedas verlo.',
      );
  String get partnerConsentRequired => _t(
        'Your partner must agree to the current privacy notice before you can send messages.',
        'Seu parceiro precisa concordar com o aviso de privacidade atual antes que você possa enviar mensagens.',
        'Tu pareja debe aceptar el aviso de privacidad actual antes de que puedas enviar mensajes.',
      );
}
