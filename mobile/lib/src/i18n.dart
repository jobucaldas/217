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
  String get save => pt ? 'Salvar' : 'Save';
  String get cancel => pt ? 'Cancelar' : 'Cancel';
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
  String get today => pt ? 'Hoje' : 'Today';
  String get recordToday => pt ? 'Registrar hoje' : 'Record today';
  String get updateToday => pt ? 'Atualizar hoje' : 'Update today';
  String get todayStatus => pt ? 'Hoje' : 'Today';
  String get remindersOn => pt ? 'Lembrete' : 'Reminder';
  String get remindersOff => pt ? 'Sem lembrete' : 'No reminder';
  String get reminderNotReady => pt ? 'Sem lembrete' : 'No reminder';
  String get legend => pt ? 'Legenda' : 'Legend';
  String get legendTaken => pt ? 'Tomado' : 'Taken';
  String get legendMissed => pt ? 'Perdido' : 'Missed';
  String get legendUnrecorded => pt ? 'Em aberto' : 'Open';
  String get takenLabel => pt ? 'Tomei' : 'Taken';
  String get missedLabel => pt ? 'Perdi' : 'Missed';
  String get pickStatus =>
      pt ? 'Como foi a tomada?' : 'How did intake go?';
}
