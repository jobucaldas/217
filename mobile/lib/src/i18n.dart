class Strings {
  const Strings(this.pt);

  final bool pt;

  String get brand => '217';
  String get continueWorkOS => pt ? 'Entrar' : 'Sign in';
  String get signInSubtitle =>
      pt ? 'calendário de anticoncepcional' : 'contraceptive calendar';
  String get logout => pt ? 'Sair' : 'Log out';
  String get settings => pt ? 'Ajustes' : 'Settings';
  String get language => pt ? 'Idioma' : 'Language';
  String get taken => pt ? 'Tomado' : 'Taken';
  String get missed => pt ? 'Perdido' : 'Missed';
  String get unrecorded => pt ? 'Em aberto' : 'Open';
  String get notes => pt ? 'Nota' : 'Note';
  String get addNote => pt ? 'Adicionar nota' : 'Add note';
  String get heartMark => pt ? 'Marcar intimidade' : 'Mark intimacy';
  String get heartMarked => pt ? 'Intimidade marcada' : 'Intimacy marked';
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
  String get advanced => pt ? 'Avançado' : 'Advanced';
  String get showMore =>
      pt ? 'Opções avançadas' : 'Advanced options';
  String get showLess =>
      pt ? 'Ocultar opções avançadas' : 'Hide advanced options';
  String get languagePortuguese => 'Português';
  String get languageEnglish => 'English';
  String get done => pt ? 'Pronto' : 'Done';
  String get clearNote => pt ? 'Limpar nota' : 'Clear note';
  String get darkMode => pt ? 'Tema escuro' : 'Dark theme';
  String get appearance => pt ? 'Aparência' : 'Appearance';
  String get themeSystem => pt ? 'Sistema' : 'System';
  String get themeLight => pt ? 'Claro' : 'Light';
  String get themeDark => pt ? 'Escuro' : 'Dark';
  String get colorTheme => pt ? 'Cor de destaque' : 'Accent';
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

  // Account / share
  String get deleteAccount => pt ? 'Excluir conta' : 'Delete account';
  String get deleteAccountWarn => pt
      ? 'Isso apaga permanentemente seus dados e a conta de login. Não dá para desfazer.'
      : 'This permanently deletes your data and login account. This cannot be undone.';
  String get deleteAccountConfirm => pt ? 'Excluir definitivamente' : 'Delete permanently';
  String get shareCalendar =>
      pt ? 'Compartilhar calendário com namorado' : 'Share calendar with boyfriend';
  String get shareInviteCode => pt ? 'Código do convite' : 'Invite code';
  String get shareCopyCode => pt ? 'Copiar código' : 'Copy code';
  String get shareEnable => pt ? 'Gerar convite' : 'Create invite';
  String get shareRevoke => pt ? 'Revogar acesso' : 'Revoke access';
  String get shareActiveWith => pt ? 'Compartilhado com' : 'Shared with';
  String get shareWaiting =>
      pt ? 'Aguardando o namorado entrar com o código.' : 'Waiting for boyfriend to join with the code.';
  String get inbox => pt ? 'Caixa de entrada' : 'Inbox';
  String get inboxEmpty => pt ? 'Nenhuma nota ainda.' : 'No notes yet.';
  String get leaveNote => pt ? 'Deixar uma nota' : 'Leave a note';
  String get sendNote => pt ? 'Enviar' : 'Send';
  String get partnerRevokedTitle => pt
      ? 'Você não está convidado ao calendário 217 dela'
      : 'You are not invited to her 217 calendar';
  String get partnerRevokedBody => pt
      ? 'Quer adicionar o código dela ou excluir esta conta?'
      : 'Add her code, or delete this account?';
  String get addHerCode => pt ? 'Adicionar código' : 'Add her code';
  String get enterInviteCode => pt ? 'Código do convite' : 'Invite code';
  String get joinCalendar => pt ? 'Entrar' : 'Join';
  String get readOnlyCalendar =>
      pt ? 'Calendário em modo leitura' : 'Read-only calendar';
  String get accountDeleted => pt ? 'Conta excluída' : 'Account deleted';
}
