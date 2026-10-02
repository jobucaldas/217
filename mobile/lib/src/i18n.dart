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
  String get loading => pt ? 'Carregando…' : 'Loading…';
  String get signInError =>
      pt ? 'Não deu para entrar. Tente de novo.' : 'Sign-in failed. Try again.';
  String get testConnection => pt ? 'Testar conexão' : 'Test connection';
  String get serverUrl =>
      pt ? 'URL do servidor próprio' : 'Self-hosted server URL';
  String get serverUrlHelp => pt
      ? 'Só para quem hospeda o próprio servidor 217. Deixe vazio para usar o servidor padrão.'
      : 'Only if you host your own 217 server. Leave empty to use the default server.';
  String get serverSaved => pt ? 'Servidor salvo' : 'Server saved';
  String get serverReset =>
      pt ? 'Usando o servidor padrão' : 'Using the default server';
  String get serverInvalid => pt
      ? 'Use um endereço completo, ex.: https://217.exemplo.com'
      : 'Enter a full address, e.g. https://217.example.com';
  String get connectionOk =>
      pt ? 'Servidor 217 encontrado' : 'Found a 217 server';
  String get connectionFail => pt
      ? 'Nenhum servidor 217 respondeu nesse endereço'
      : 'No 217 server answered at that address';
  String serverLabel(String host) => pt ? 'Servidor: $host' : 'Server: $host';
  String get genericError =>
      pt ? 'Algo deu errado. Tente de novo.' : 'Something went wrong. Try again.';
  String get connectionError => pt
      ? 'Sem conexão com o servidor. Tente de novo.'
      : "Can't reach the server. Try again.";
  String get retry => pt ? 'Tentar de novo' : 'Retry';
  String get showMore =>
      pt ? 'Opções avançadas' : 'Advanced options';
  String get showLess =>
      pt ? 'Ocultar opções avançadas' : 'Hide advanced options';
  String get languagePortuguese => 'Português';
  String get languageEnglish => 'English';
  String get done => pt ? 'Pronto' : 'Done';
  String get clearNote => pt ? 'Limpar nota' : 'Clear note';
  String get appearance => pt ? 'Aparência' : 'Appearance';
  String get themeSystem => pt ? 'Sistema' : 'System';
  String get themeLight => pt ? 'Claro' : 'Light';
  String get themeDark => pt ? 'Escuro' : 'Dark';
  String get colorTheme => pt ? 'Cor de destaque' : 'Accent';
  String get paletteAzure => pt ? 'Azul' : 'Azure';
  String get paletteMint => pt ? 'Menta' : 'Mint';
  String get palettePlum => pt ? 'Ameixa' : 'Plum';
  String get today => pt ? 'Hoje' : 'Today';
  String get previousMonth => pt ? 'Mês anterior' : 'Previous month';
  String get nextMonth => pt ? 'Próximo mês' : 'Next month';
  String get recordToday => pt ? 'Registrar hoje' : 'Record today';
  String get updateToday => pt ? 'Atualizar hoje' : 'Update today';
  String get remindersOff => pt ? 'Lembrete desligado' : 'Reminder off';
  String get reminderNotReady =>
      pt ? 'Lembrete ainda não configurado' : 'Reminder not set up yet';
  String get reminderHint => pt
      ? 'Depois de entrar, configure um lembrete diário em Ajustes.'
      : 'After signing in, set a daily reminder in Settings.';
  String get reminderHintDismiss => pt ? 'Entendi' : 'Got it';
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
      ? 'Lembretes ainda não funcionam neste navegador. Use o app Android para receber notificações.'
      : "Reminders don't work in this browser yet. Use the Android app to get notifications.";
  String get reminderReady => pt ? 'Lembrete ativo' : 'Reminder on';
  String get reminderNativeNote => pt
      ? 'No Android, o lembrete é uma notificação diária neste aparelho. No navegador, depende do servidor ter notificações push.'
      : 'On Android, the reminder is a daily notification on this device. In the browser, it depends on the server supporting push notifications.';
  String get reminderPermissionDenied => pt
      ? 'Permissão de notificação negada neste aparelho.'
      : 'Notification permission denied on this device.';
  String get reminderLocalScheduled => pt
      ? 'Notificação local agendada neste aparelho'
      : 'Local notification scheduled on this device';

  String get reminderWebNeedsPush => pt
      ? 'Neste navegador, o lembrete em segundo plano precisa de notificações push do servidor.'
      : 'In this browser, background reminders need push notifications from the server.';

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
  String get codeCopied => pt ? 'Código copiado' : 'Code copied';
  String get shareEnable => pt ? 'Gerar convite' : 'Create invite';
  String get shareRevoke => pt ? 'Revogar acesso' : 'Revoke access';
  String get shareActiveWith => pt ? 'Compartilhado com' : 'Shared with';
  String get shareWaiting =>
      pt ? 'Aguardando o namorado entrar com o código.' : 'Waiting for boyfriend to join with the code.';
  String get inbox => pt ? 'Caixa de entrada' : 'Inbox';
  String get inboxEmpty => pt ? 'Nenhuma nota ainda.' : 'No notes yet.';
  String get leaveNote => pt ? 'Deixar uma nota' : 'Leave a note';
  String get sendNote => pt ? 'Enviar' : 'Send';
  String get noteSent => pt ? 'Nota enviada' : 'Note sent';
  String get partnerRevokedTitle => pt
      ? 'Você não está convidado ao calendário 217 dela'
      : 'You are not invited to her 217 calendar';
  String get partnerRevokedBody => pt
      ? 'Quer adicionar o código dela ou excluir esta conta?'
      : 'Add her code, or delete this account?';
  String get enterInviteCode => pt ? 'Código do convite' : 'Invite code';
  String get inviteCodeRejected => pt
      ? 'Esse código não funcionou. Confira e tente de novo.'
      : "That code didn't work. Check it and try again.";
  String get joinCalendar => pt ? 'Entrar' : 'Join';
  String get readOnlyCalendar =>
      pt ? 'Calendário em modo leitura' : 'Read-only calendar';
  String get accountDeleted => pt ? 'Conta excluída' : 'Account deleted';
}
