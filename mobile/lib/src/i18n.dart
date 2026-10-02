/// UI languages. English is the default until someone picks another one.
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

  static AppLanguage fromId(String? raw) => AppLanguage.values.firstWhere(
        (l) => l.id == raw,
        orElse: () => AppLanguage.en,
      );
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
  String get heartMark =>
      _t('Mark intimacy', 'Marcar intimidade', 'Marcar intimidad');
  String get heartMarked =>
      _t('Intimacy marked', 'Intimidade marcada', 'Intimidad marcada');
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
  String serverLabel(String host) =>
      _t('Server: $host', 'Servidor: $host', 'Servidor: $host');
  String get selfHostTip => _t(
        'Hosting your own 217 server? Set it up in Settings.',
        'Tem seu próprio servidor 217? Configure em Ajustes.',
        '¿Tienes tu propio servidor 217? Configúralo en Ajustes.',
      );
  String get selfHostCard => _t(
        'You can run 217 on your own server and keep your data there.',
        'Você pode rodar o 217 no seu próprio servidor e manter seus dados lá.',
        'Puedes ejecutar 217 en tu propio servidor y guardar tus datos allí.',
      );
  String get selfHostGuide =>
      _t('Self-hosting guide', 'Guia de hospedagem própria', 'Guía para alojarlo tú');
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
  String get paletteAzure => _t('Azure', 'Azul', 'Azul');
  String get paletteMint => _t('Mint', 'Menta', 'Menta');
  String get palettePlum => _t('Plum', 'Ameixa', 'Ciruela');
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
        'After signing in, set a daily reminder in Settings.',
        'Depois de entrar, configure um lembrete diário em Ajustes.',
        'Después de iniciar sesión, configura un recordatorio diario en Ajustes.',
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
        "Reminders don't work in this browser yet. Use the Android app to get notifications.",
        'Lembretes ainda não funcionam neste navegador. Use o app Android para receber notificações.',
        'Los recordatorios aún no funcionan en este navegador. Usa la app de Android para recibir notificaciones.',
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
  String get deleteAccount => _t('Delete account', 'Excluir conta', 'Eliminar cuenta');
  String get deleteAccountWarn => _t(
        'This permanently deletes your data and login account. This cannot be undone.',
        'Isso apaga permanentemente seus dados e a conta de login. Não dá para desfazer.',
        'Esto elimina de forma permanente tus datos y tu cuenta. No se puede deshacer.',
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
        'Share calendar with boyfriend',
        'Compartilhar calendário com namorado',
        'Compartir calendario con tu novio',
      );
  String get shareInviteCode =>
      _t('Invite code', 'Código do convite', 'Código de invitación');
  String get shareInviteLink =>
      _t('Invite link', 'Link do convite', 'Enlace de invitación');
  String get shareSend =>
      _t('Send invite', 'Enviar convite', 'Enviar invitación');
  String get shareCopyCode => _t('Copy code', 'Copiar código', 'Copiar código');
  String get shareCopyLink => _t('Copy link', 'Copiar link', 'Copiar enlace');
  String get codeCopied => _t('Code copied', 'Código copiado', 'Código copiado');
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

  String get shareEnable => _t('Create invite', 'Gerar convite', 'Crear invitación');
  String get shareRevoke => _t('Revoke access', 'Revogar acesso', 'Revocar acceso');
  String get shareActiveWith =>
      _t('Shared with', 'Compartilhado com', 'Compartido con');
  String get shareWaiting => _t(
        'Waiting for boyfriend to join with the link or code.',
        'Aguardando o namorado entrar pelo link ou código.',
        'Esperando a que tu novio se una con el enlace o el código.',
      );

  // Sharing (partner side)
  String get joinWithCode => _t(
        'Join a calendar with a code',
        'Entrar em um calendário com código',
        'Unirse a un calendario con un código',
      );
  String get joinWithCodeHint => _t(
        'Got an invite? Enter the code here.',
        'Recebeu um convite? Use o código aqui.',
        '¿Recibiste una invitación? Introduce el código aquí.',
      );
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
  String get leaveNote => _t('Leave a note', 'Deixar uma nota', 'Dejar una nota');
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
}
