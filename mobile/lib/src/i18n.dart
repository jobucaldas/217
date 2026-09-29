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
  String get notes => pt ? 'Notas' : 'Notes';
  String get save => pt ? 'Salvar' : 'Save';
  String get cancel => pt ? 'Cancelar' : 'Cancel';
  String get back => pt ? 'Voltar' : 'Back';
  String get loading => pt ? 'Carregando…' : 'Loading…';
  String get signInError =>
      pt ? 'Falha ao entrar. Tente novamente.' : 'Sign-in failed. Try again.';
}
