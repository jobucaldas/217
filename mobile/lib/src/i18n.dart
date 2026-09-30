class Strings {
  const Strings(this.pt);

  final bool pt;

  String get brand => '217';
  String get continueWorkOS =>
      pt ? 'Continuar com WorkOS' : 'Continue with WorkOS';
  String get signInSubtitle => pt
      ? 'Controle o uso do anticoncepcional no calendário.'
      : 'Track anticonceptional intake on the calendar.';
  String get logout => pt ? 'Sair' : 'Log out';
  String get settings => pt ? 'Configurações' : 'Settings';
  String get language => pt ? 'Idioma' : 'Language';
  String get taken => pt ? 'Tomado' : 'Taken';
  String get missed => pt ? 'Não tomado' : 'Missed';
  String get unrecorded => pt ? 'Não registrado' : 'Not recorded';
  String get notes => pt ? 'Notas' : 'Notes';
  String get save => pt ? 'Salvar' : 'Save';
  String get cancel => pt ? 'Cancelar' : 'Cancel';
  String get back => pt ? 'Voltar' : 'Back';
  String get loading => pt ? 'Carregando…' : 'Loading…';
  String get signInError =>
      pt ? 'Falha ao entrar. Tente novamente.' : 'Sign-in failed. Try again.';
  String get apiBaseUrl => pt ? 'URL da API' : 'API base URL';
  String get apiBaseHint => pt
      ? 'Emulador: http://10.0.2.2:8787 — aparelho: http://SEU_IP:8787'
      : 'Emulator: http://10.0.2.2:8787 — device: http://YOUR_LAN_IP:8787';
  String get testConnection => pt ? 'Testar conexão' : 'Test connection';
  String get connectionOk => pt ? 'API acessível' : 'API reachable';
  String get connectionFail => pt ? 'API inacessível' : 'API unreachable';
  String get darkMode => pt ? 'Tema escuro' : 'Dark theme';
  String get today => pt ? 'Hoje' : 'Today';
  String get todayStatus => pt ? 'Status de hoje' : "Today's status";
  String get remindersOn => pt ? 'Lembrete ativado' : 'Reminder on';
  String get remindersOff => pt ? 'Lembrete desativado' : 'Reminder off';
  String get reminderNotReady =>
      pt ? 'Lembretes não configurados neste dispositivo.' : 'Reminders not configured on this device.';
  String get legend => pt ? 'Legenda de status' : 'Status legend';
  String get legendTaken => pt ? 'Tomado' : 'Taken';
  String get legendMissed => pt ? 'Não tomado' : 'Missed';
  String get legendUnrecorded => pt ? 'Não registrado' : 'Not recorded';
  String get takenLabel => pt ? '✓ Tomei' : '✓ Taken';
  String get missedLabel => pt ? '✗ Não tomei' : '✗ Missed';
}
