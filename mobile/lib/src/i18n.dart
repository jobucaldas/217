class Strings {
  const Strings(this.pt);

  final bool pt;

  String get brand => '217';
  String get continueWorkOS => pt ? 'Entrar' : 'Sign in';
  String get signInSubtitle =>
      pt ? 'Seu calendário de tomada.' : 'Your intake calendar.';
  String get logout => pt ? 'Sair' : 'Log out';
  String get settings => pt ? 'Ajustes' : 'Settings';
  String get language => pt ? 'Idioma' : 'Language';
  String get taken => pt ? 'Tomado' : 'Taken';
  String get missed => pt ? 'Perdido' : 'Missed';
  String get unrecorded => pt ? 'Em aberto' : 'Open';
  String get notes => pt ? 'Nota' : 'Note';
  String get addNote => pt ? 'Adicionar nota' : 'Add note';
  String get save => pt ? 'Salvar' : 'Save';
  String get cancel => pt ? 'Cancelar' : 'Cancel';
  String get clearMark => pt ? 'Remover marcação' : 'Clear mark';
  String get back => pt ? 'Voltar' : 'Back';
  String get loading => pt ? 'Carregando…' : 'Loading…';
  String get signInError =>
      pt ? 'Não deu para entrar. Tente de novo.' : 'Sign-in failed. Try again.';
  String get apiBaseUrl => pt ? 'URL da API' : 'API base URL';
  String get apiBaseHint => pt
      ? 'Emulador: http://10.0.2.2:8787 — aparelho: http://SEU_IP:8787'
      : 'Emulator: http://10.0.2.2:8787 — device: http://YOUR_LAN_IP:8787';
  String get testConnection => pt ? 'Testar conexão' : 'Test connection';
  String get connectionOk => pt ? 'API acessível' : 'API reachable';
  String get connectionFail => pt ? 'API inacessível' : 'API unreachable';
  String get darkMode => pt ? 'Tema escuro' : 'Dark theme';
  String get appearance => pt ? 'Aparência' : 'Appearance';
  String get themeSystem => pt ? 'Sistema' : 'System';
  String get themeLight => pt ? 'Claro' : 'Light';
  String get themeDark => pt ? 'Escuro' : 'Dark';
  String get colorTheme => pt ? 'Cores' : 'Colors';
  String get paletteAzure => pt ? 'Azul' : 'Azure';
  String get paletteMint => pt ? 'Menta' : 'Mint';
  String get palettePlum => pt ? 'Ameixa' : 'Plum';
  String get today => pt ? 'Hoje' : 'Today';
  String get recordToday => pt ? 'Registrar hoje' : 'Record today';
  String get updateToday => pt ? 'Atualizar hoje' : 'Update today';
  String get todayStatus => pt ? 'Hoje' : 'Today';
  String get remindersOn => pt ? 'Lembrete' : 'Reminder';
  String get remindersOff => pt ? 'Lembrete desligado' : 'Reminder off';
  String get reminderNotReady =>
      pt ? 'Lembrete ainda não configurado' : 'Reminder not set up yet';
  String get reminderHint => pt
      ? 'Configure um lembrete diário em Ajustes. No Android usamos notificações do sistema.'
      : 'Set a daily reminder in Settings. On Android we use system notifications.';
  String get reminderHintDismiss => pt ? 'Entendi' : 'Got it';
  String get legend => pt ? 'Legenda' : 'Legend';
  String get legendTaken => pt ? 'Tomado' : 'Taken';
  String get legendMissed => pt ? 'Perdido' : 'Missed';
  String get legendUnrecorded => pt ? 'Em aberto' : 'Open';
  String get takenLabel => pt ? 'Tomei' : 'Taken';
  String get missedLabel => pt ? 'Perdi' : 'Missed';
  String get pickStatus =>
      pt ? 'Como foi a tomada?' : 'How did intake go?';
  String get reminders => pt ? 'Lembrete' : 'Reminder';
  String get reminderTime => pt ? 'Horário' : 'Time';
  String get reminderEnable => pt ? 'Lembrar todo dia' : 'Remind me daily';
  String get reminderSaved => pt ? 'Salvo' : 'Saved';
  String get reminderNeedsPush => pt
      ? 'Ative as notificações do sistema neste aparelho.'
      : 'Enable system notifications on this device.';
  String get reminderUnavailable => pt
      ? 'Neste navegador, lembretes web precisam de push (VAPID). No Android usamos notificações nativas.'
      : 'In this browser, web reminders need push (VAPID). On Android we use native notifications.';
  String get reminderReady => pt ? 'Lembrete ativo' : 'Reminder on';
  String get reminderNativeNote => pt
      ? 'Android: notificação local diária do sistema. Web: push do servidor (VAPID) quando disponível.'
      : 'Android: daily system local notification. Web: server push (VAPID) when available.';
  String get reminderPermissionDenied => pt
      ? 'Permissão de notificação negada neste aparelho.'
      : 'Notification permission denied on this device.';
  String get reminderLocalScheduled => pt
      ? 'Notificação local agendada neste aparelho'
      : 'Local notification scheduled on this device';
  String get reminderWebNeedsPush => pt
      ? 'Neste navegador, entrega em segundo plano precisa de push do servidor.'
      : 'In this browser, background delivery needs server push.';
}
