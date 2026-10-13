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

  /// Sunday-first weekday initials for the month grid.
  List<String> get weekdayInitials => switch (language) {
        AppLanguage.en => const ['S', 'M', 'T', 'W', 'T', 'F', 'S'],
        AppLanguage.pt => const ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'],
        AppLanguage.es => const ['D', 'L', 'M', 'X', 'J', 'V', 'S'],
      };

  String get brand => '217';
  String get continueWorkOS => _t('Sign in', 'Entrar', 'Iniciar sesión');
  String get signInSubtitle => _t(
        'contraceptive calendar',
        'calendário de anticoncepcional',
        'calendario de anticonceptivos',
      );
  String get logout => _t('Log out', 'Sair', 'Cerrar sesión');
  String get settings => _t('Settings', 'Ajustes', 'Ajustes');
  String get languageLabel => _t('Language', 'Idioma', 'Idioma');
  String get taken => _t('Taken', 'Tomado', 'Tomada');
  String get missed => _t('Missed', 'Perdido', 'Olvidada');
  String get unrecorded => _t('Open', 'Em aberto', 'Pendiente');
  String get notes => _t('Note', 'Nota', 'Nota');
  String get addNote => _t('Add note', 'Adicionar nota', 'Añadir nota');
  String get heartLabel => _t('Intimacy', 'Intimidade', 'Intimidad');
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
  String get selfHostTip => _t(
        'Hosting your own 217 server? Set it up in Settings.',
        'Tem seu próprio servidor 217? Configure em Ajustes.',
        '¿Tienes tu propio servidor 217? Configúralo en Ajustes.',
      );
  String get selfHostBlurb => _t(
        'Run 217 on your own server and keep your data there.',
        'Rode o 217 no seu próprio servidor e mantenha seus dados lá.',
        'Ejecuta 217 en tu propio servidor y guarda tus datos allí.',
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
  String get previousMonth =>
      _t('Previous month', 'Mês anterior', 'Mes anterior');
  String get nextMonth => _t('Next month', 'Próximo mês', 'Mes siguiente');
  String get recordToday =>
      _t('Record today', 'Registrar hoje', 'Registrar hoy');
  String get updateToday =>
      _t('Update today', 'Atualizar hoje', 'Actualizar hoy');

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
  String get legendTaken => taken;
  String get legendMissed => missed;
  String get legendUnrecorded => unrecorded;
  String get takenLabel => _t('Taken', 'Tomei', 'La tomé');
  String get missedLabel => _t('Missed', 'Perdi', 'La olvidé');
  String get reminders => _t('Reminder', 'Lembrete', 'Recordatorio');
  String get reminderTime => _t('Time', 'Horário', 'Hora');
  String get reminderEnable =>
      _t('Remind me daily', 'Lembrar todo dia', 'Recordarme cada día');
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

  // Account
  String get deleteAccount =>
      _t('Delete account', 'Excluir conta', 'Eliminar cuenta');
  String deleteAccountWarn(bool deletesLogin) => deletesLogin ? _t(
        'This permanently deletes your data and WorkOS sign-in identity, and withdraws your consent. This cannot be undone.',
        'Isso apaga permanentemente seus dados e sua identidade de login da WorkOS, e revoga seu consentimento. Não dá para desfazer.',
        'Esto elimina permanentemente tus datos y tu identidad de inicio de sesión de WorkOS, y retira tu consentimiento. No se puede deshacer.',
      ) : _t(
        'This permanently deletes your data on this server and withdraws your consent. Your WorkOS login identity remains. This cannot be undone.',
        'Isso apaga permanentemente seus dados neste servidor e revoga seu consentimento. Sua identidade de login da WorkOS permanece. Não dá para desfazer.',
        'Esto elimina permanentemente tus datos en este servidor y retira tu consentimiento. Tu identidad de inicio de sesión de WorkOS permanece. No se puede deshacer.',
      );
  String get deleteAccountConfirm => _t(
        'Delete permanently',
        'Excluir definitivamente',
        'Eliminar definitivamente',
      );
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
  String get inbox => _t('Inbox', 'Caixa de entrada', 'Bandeja de entrada');
  String get inboxEmpty =>
      _t('No notes yet.', 'Nenhuma nota ainda.', 'Aún no hay notas.');
  String get leaveNote =>
      _t('Leave a note', 'Deixar uma nota', 'Dejar una nota');
  String get sendNote => _t('Send', 'Enviar', 'Enviar');
  String get noteSent => _t('Note sent', 'Nota enviada', 'Nota enviada');
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
  String get readOnlyCalendar => _t(
        'Read-only calendar',
        'Calendário em modo leitura',
        'Calendario de solo lectura',
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
  String get legendPeriod => periodLabel;
  String get legendPms => _t('PMS', 'TPM', 'SPM');
  String cycleNext(String period, String pms) => _t(
        'Next period ~$period · PMS from $pms',
        'Próxima menstruação ~$period · TPM a partir de $pms',
        'Próxima regla ~$period · SPM desde $pms',
      );
  String cycleNextNoPms(String period) => _t(
        'Next period ~$period',
        'Próxima menstruação ~$period',
        'Próxima regla ~$period',
      );
  String cyclePmsNow(String period) => _t(
        'PMS likely now · period ~$period',
        'Provável TPM agora · menstruação ~$period',
        'Posible SPM ahora · regla ~$period',
      );
  String get cyclePeriodNow => _t(
        'Period expected around now',
        'Menstruação prevista para agora',
        'Regla prevista para estos días',
      );
  String get cycleHintOwner => _t(
        'Mark period days to see PMS predictions',
        'Marque os dias de menstruação para ver a previsão de TPM',
        'Marca los días de regla para ver la previsión de SPM',
      );
  String cycleStageNote(String code) => switch (code) {
        'pms_suppressed_menopause' => _t('217 counts no PMS because you told 217 you are in menopause.', 'O 217 não conta TPM porque você informou ao 217 que está na menopausa.', '217 no cuenta el SPM porque le dijiste a 217 que estás en la menopausia.'),
        'pms_counted_perimenopause' => _t('You told 217 you are in perimenopause. Cycles can still happen, so PMS is still counted.', 'Você informou ao 217 que está na perimenopausa. Ciclos ainda podem ocorrer, então a TPM continua sendo contada.', 'Le dijiste a 217 que estás en la perimenopausia. Aún puede haber ciclos, así que se sigue contando el SPM.'),
        _ => '',
      };
  String get reproductiveStage => _t('Reproductive stage', 'Fase reprodutiva', 'Etapa reproductiva');
  String get stageCycling => _t('Cycling', 'Com ciclos', 'Con ciclos');
  String get stagePerimenopause => _t('Perimenopause', 'Perimenopausa', 'Perimenopausia');
  String get stageMenopause => _t('Menopause', 'Menopausa', 'Menopausia');
  String get stageSelfReport => _t('This is what you told 217; it is not a diagnosis.', 'Isto é o que você informou ao 217; não é um diagnóstico.', 'Esto es lo que le dijiste a 217; no es un diagnóstico.');
  String get pmsNotCounted => _t('PMS is not counted while menopause is selected.', 'A TPM não é contada enquanto menopausa estiver selecionada.', 'El SPM no se cuenta mientras esté seleccionada la menopausia.');

  // Partner alerts
  String get partnerAlerts => _t('Alerts', 'Avisos', 'Avisos');
  String get partnerAlertsSubtitle => _t(
        'PMS and pill not logged',
        'TPM e pílula não registrada',
        'SPM y píldora no registrada',
      );
  String get pmsAlertTitle =>
      _t('PMS heads-up', 'Aviso de TPM', 'Aviso de SPM');
  String get pmsAlertBody => _t(
        'On the day her PMS is predicted to start',
        'No dia em que a TPM dela deve começar',
        'El día en que se prevé que empiece su SPM',
      );
  String get pillAlertTitle => _t(
        'Pill not logged',
        'Pílula não registrada',
        'Píldora no registrada',
      );
  String get pillAlertBody => _t(
        "If today's pill isn't logged by this time",
        'Se a pílula de hoje não estiver registrada até esse horário',
        'Si la píldora de hoy no está registrada a esta hora',
      );
  String get partnerAlertsNote => _t(
        'Alerts are scheduled on this phone from her latest calendar each time 217 syncs, so open it now and then.',
        'Os avisos são agendados neste celular com o calendário mais recente dela sempre que o 217 sincroniza, então abra o app de vez em quando.',
        'Los avisos se programan en este teléfono con su calendario más reciente cada vez que 217 se sincroniza, así que ábrelo de vez en cuando.',
      );
  String get partnerAlertsWeb => _t(
        'Alerts are delivered by the Android app.',
        'Os avisos são entregues pelo app Android.',
        'Los avisos los entrega la app de Android.',
      );
  String get partnerAlertsNeedLink => _t(
        'Alerts start once you join her calendar.',
        'Os avisos começam quando você entrar no calendário dela.',
        'Los avisos empiezan cuando te unas a su calendario.',
      );
  String partnerName(String name) =>
      name.trim().isEmpty ? _t('She', 'Ela', 'Ella') : name.trim();
  String get pmsNotifTitle => _t(
        'PMS may start today',
        'A TPM pode começar hoje',
        'El SPM puede empezar hoy',
      );
  String pmsNotifBody(String name, String period) => _t(
        '${partnerName(name)}: PMS days predicted from today, period ~$period.',
        '${partnerName(name)}: TPM prevista a partir de hoje, menstruação ~$period.',
        '${partnerName(name)}: SPM previsto desde hoy, regla ~$period.',
      );
  String get pillNotifTitle => _t(
        'Pill not logged yet',
        'Pílula ainda não registrada',
        'Píldora aún no registrada',
      );
  String pillNotifBody(String name) => _t(
        "${partnerName(name)} hadn't logged today's pill when 217 last synced.",
        '${partnerName(name)} não tinha registrado a pílula de hoje na última sincronização do 217.',
        '${partnerName(name)} no había registrado la píldora de hoy en la última sincronización de 217.',
      );

  // Privacy (LGPD)
  String get privacyTitle => _t('Your data and privacy',
      'Seus dados e privacidade', 'Tus datos y privacidad');
  String get privacyNotice =>
      _t('Privacy notice', 'Aviso de privacidade', 'Aviso de privacidad');
  String get privacySensitiveTitle => _t(
        'Sensitive health data',
        'Dados sensíveis de saúde',
        'Datos sensibles de salud',
      );
  String get privacySensitiveBody => _t(
        "217 records when you take your contraceptive, missed days, notes, intimacy and period days. Under Brazil's LGPD (Law 13.709/2018) this is sensitive data about health and sex life, so it is only processed with your specific consent.",
        '217 registra quando você toma o anticoncepcional, dias esquecidos, notas, intimidade e dias de menstruação. Pela LGPD (Lei 13.709/2018) são dados sensíveis de saúde e vida sexual, por isso só são tratados com o seu consentimento específico.',
        '217 registra cuándo tomas el anticonceptivo, días olvidados, notas, intimidad y días de regla. Según la LGPD de Brasil (Ley 13.709/2018) son datos sensibles de salud y vida sexual, por eso solo se tratan con tu consentimiento específico.',
      );
  String get privacyWhatTitle =>
      _t('What is stored', 'O que é guardado', 'Qué se guarda');
  String get privacyWhatBody => _t(
        'Your email and name from sign-in, your calendar entries, notes between you and your partner, and your reminder and alert times.',
        'Seu email e nome do login, os registros do calendário, as notas entre você e seu parceiro, e os horários de lembretes e alertas.',
        'Tu email y nombre del inicio de sesión, los registros del calendario, las notas entre tú y tu pareja, y las horas de recordatorios y alertas.',
      );
  String get privacyWhyTitle => _t('Why', 'Para quê', 'Para qué');
  String get privacyWhyBody => _t(
        'Only to show your calendar and stats, predict periods and PMS, remind you, and share the calendar read-only with the one partner you invite. Never for ads or profiling, and never sold.',
        'Só para mostrar seu calendário e estatísticas, prever menstruação e TPM, lembrar você e compartilhar o calendário, só para leitura, com o parceiro que você convidar. Nunca para anúncios ou perfilamento, e nunca vendidos.',
        'Solo para mostrar tu calendario y estadísticas, predecir la regla y el SPM, recordarte y compartir el calendario, solo lectura, con la pareja que invites. Nunca para anuncios o perfiles, y nunca se venden.',
      );
  String get privacyWhereTitle => _t('Where and who sees it',
      'Onde fica e quem vê', 'Dónde está y quién lo ve');
  String privacyWhereBody(String server) => _t(
        'On the server $server, run by its operator (the controller). It is encrypted in transit (TLS). Calendar entries, notes, names and emails are encrypted at rest with AES-256. Reminder times, alert times and operational timestamps are stored so the app can run and are not sealed. Only you and a partner you invite see your calendar. Sign-in is handled by WorkOS, which receives your email.',
        'No servidor $server, mantido por quem o opera (o controlador). Fica criptografado em trânsito (TLS). Registros do calendário, notas, nomes e emails são criptografados em repouso com AES-256. Horários de lembretes e alertas e registros operacionais são guardados para o app funcionar e não são selados. Só você e o parceiro que você convidar veem seu calendário. O login é feito pela WorkOS, que recebe seu email.',
        'En el servidor $server, gestionado por quien lo opera (el responsable). Está cifrado en tránsito (TLS). Las entradas del calendario, notas, nombres y correos están cifrados en reposo con AES-256. Las horas de recordatorios y alertas y las marcas operativas se guardan para que funcione la app y no están selladas. Solo tú y la pareja que invites ven tu calendario. El inicio de sesión lo hace WorkOS, que recibe tu email.',
      );
  String get privacyRightsTitle =>
      _t('Your rights', 'Seus direitos', 'Tus derechos');
  String get privacyRightsBody => _t(
        'Download all your data, correct any day, stop sharing, or delete your account and everything in it at any time in Settings. Deleting the account withdraws this consent.',
        'Baixe todos os seus dados, corrija qualquer dia, pare de compartilhar ou exclua sua conta e tudo nela quando quiser, em Ajustes. Excluir a conta revoga este consentimento.',
        'Descarga todos tus datos, corrige cualquier día, deja de compartir o elimina tu cuenta y todo su contenido cuando quieras, en Ajustes. Eliminar la cuenta retira este consentimiento.',
      );
  String get privacyContactTitle => _t('Contact', 'Contato', 'Contacto');
  String privacyContactBody(String? contact) =>
      contact ??
      _t(
        'Ask whoever runs this server.',
        'Fale com quem opera este servidor.',
        'Pregunta a quien opera este servidor.',
      );
  String get consentCheckbox => _t(
        'I agree to 217 processing my health data for these purposes.',
        'Concordo que o 217 trate meus dados de saúde para essas finalidades.',
        'Acepto que 217 trate mis datos de salud para estos fines.',
      );
  String get consentAccept =>
      _t('Agree and continue', 'Concordar e continuar', 'Aceptar y continuar');
  String get consentDecline =>
      _t('Not now (sign out)', 'Agora não (sair)', 'Ahora no (cerrar sesión)');
  String get downloadData =>
      _t('Download my data', 'Baixar meus dados', 'Descargar mis datos');
  String get downloadDataBlurb => _t(
        'Everything this server holds about you, as a JSON file.',
        'Tudo que este servidor guarda sobre você, em um arquivo JSON.',
        'Todo lo que este servidor guarda sobre ti, en un archivo JSON.',
      );
  String dataSavedTo(String where) => _t(
        'Saved to $where',
        'Salvo em $where',
        'Guardado en $where',
      );
  String get dataDownloaded =>
      _t('Download started', 'Download iniciado', 'Descarga iniciada');
  String get dataCopied => _t(
        'Data copied to the clipboard',
        'Dados copiados para a área de transferência',
        'Datos copiados al portapapeles',
      );
}
