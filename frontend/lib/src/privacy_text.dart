import 'i18n.dart';

/// Wording of the privacy notice (LGPD arts. 9, 11, 18) and of the account
/// deletion page, in the app's languages.
class PrivacyText {
  const PrivacyText(this.language);

  final AppLanguage language;

  String _t(String en, String pt, String es) => switch (language) {
        AppLanguage.en => en,
        AppLanguage.pt => pt,
        AppLanguage.es => es,
      };

  String get title =>
      _t('Privacy notice', 'Aviso de privacidade', 'Aviso de privacidad');
  String get intro => _t(
        'What 217 stores about you, why, and what you can do about it.',
        'O que o 217 guarda sobre você, para quê, e o que você pode fazer.',
        'Qué guarda 217 sobre ti, para qué y qué puedes hacer al respecto.',
      );

  String get sensitiveTitle => _t('Sensitive health data',
      'Dados sensíveis de saúde', 'Datos sensibles de salud');
  String get sensitiveBody => _t(
        "217 records when you take your contraceptive, missed days, notes, sex and period days. Under Brazil's LGPD (Law 13.709/2018) this is sensitive data about health and sex life, so it is only processed with your specific consent.",
        '217 registra quando você toma o anticoncepcional, dias esquecidos, notas, sexo e dias de menstruação. Pela LGPD (Lei 13.709/2018) são dados sensíveis de saúde e vida sexual, por isso só são tratados com o seu consentimento específico.',
        '217 registra cuándo tomas el anticonceptivo, días olvidados, notas, sexo y días de regla. Según la LGPD de Brasil (Ley 13.709/2018) son datos sensibles de salud y vida sexual, por eso solo se tratan con tu consentimiento específico.',
      );

  String get whatTitle =>
      _t('What is stored', 'O que é guardado', 'Qué se guarda');
  String get whatBody => _t(
        'Your email and name from sign-in, the display name you choose (shown to your partner), your birth month and reproductive stage if you give them, your calendar entries, messages between you and your partner, and your reminder and alert times.',
        'Seu email e nome do login, o nome de exibição que você escolher (mostrado ao parceiro), seu mês de nascimento e fase reprodutiva se você informar, os registros do calendário, as mensagens entre você e seu parceiro, e os horários de lembretes e alertas.',
        'Tu email y nombre del inicio de sesión, el nombre visible que elijas (lo ve tu pareja), tu mes de nacimiento y etapa reproductiva si los indicas, los registros del calendario, los mensajes entre tú y tu pareja, y las horas de recordatorios y alertas.',
      );

  String get whyTitle => _t('Why', 'Para quê', 'Para qué');
  String get whyBody => _t(
        'Only to show your calendar and stats, predict periods and PMS, suggest a reproductive stage from your age and period history, remind you, and share the calendar read-only with the one partner you invite. Never for ads or profiling, and never sold.',
        'Só para mostrar seu calendário e estatísticas, prever menstruação e TPM, sugerir uma fase reprodutiva pela sua idade e histórico de menstruação, lembrar você e compartilhar o calendário, só para leitura, com o parceiro que você convidar. Nunca para anúncios ou perfilamento, e nunca vendidos.',
        'Solo para mostrar tu calendario y estadísticas, predecir la regla y el SPM, sugerir una etapa reproductiva según tu edad e historial de reglas, recordarte y compartir el calendario, solo lectura, con la pareja que invites. Nunca para anuncios o perfiles, y nunca se venden.',
      );

  String get whereTitle => _t('Where and who sees it', 'Onde fica e quem vê',
      'Dónde está y quién lo ve');
  String whereBody(String server) => _t(
        'On the server $server, run by its operator (the controller). It is encrypted in transit (TLS). Calendar entries, notes, names, display names, emails, birth month and reproductive stage are encrypted at rest with AES-256. Reminder times, alert times and operational timestamps are stored so the app can run and are not sealed. Only you and a partner you invite see your calendar. Sign-in is handled by WorkOS, which receives your email.',
        'No servidor $server, mantido por quem o opera (o controlador). Fica criptografado em trânsito (TLS). Registros do calendário, notas, nomes, nomes de exibição, emails, mês de nascimento e fase reprodutiva são criptografados em repouso com AES-256. Horários de lembretes e alertas e registros operacionais são guardados para o app funcionar e não são selados. Só você e o parceiro que você convidar veem seu calendário. O login é feito pela WorkOS, que recebe seu email.',
        'En el servidor $server, gestionado por quien lo opera (el responsable). Está cifrado en tránsito (TLS). Las entradas del calendario, notas, nombres, nombres visibles, correos, mes de nacimiento y etapa reproductiva están cifrados en reposo con AES-256. Las horas de recordatorios y alertas y las marcas operativas se guardan para que funcione la app y no están selladas. Solo tú y la pareja que invites ven tu calendario. El inicio de sesión lo hace WorkOS, que recibe tu email.',
      );

  String get rightsTitle => _t('Your rights', 'Seus direitos', 'Tus derechos');
  String get rightsBody => _t(
        'Correct any day or stop sharing in the app. On this page you can download all your data, withdraw your consent, or delete your account and everything in it, at any time.',
        'Corrija qualquer dia ou pare de compartilhar no app. Nesta página você pode baixar todos os seus dados, revogar seu consentimento ou excluir sua conta e tudo nela, quando quiser.',
        'Corrige cualquier día o deja de compartir en la app. En esta página puedes descargar todos tus datos, retirar tu consentimiento o eliminar tu cuenta y todo su contenido, cuando quieras.',
      );

  String get contactTitle => _t('Contact', 'Contato', 'Contacto');
  String get contactNone => _t(
        'Ask whoever runs this server.',
        'Fale com quem opera este servidor.',
        'Pregunta a quien opera este servidor.',
      );

  String get yourDataTitle => _t('Your data', 'Seus dados', 'Tus datos');
  String signedInAs(String email) => _t(
        'Signed in as $email.',
        'Conectado como $email.',
        'Sesión iniciada como $email.',
      );
  String get noConsent => _t(
        'You have not agreed to this notice, so 217 does not process your data until you agree in the app.',
        'Você não concordou com este aviso, então o 217 não trata seus dados até você concordar no app.',
        'No has aceptado este aviso, así que 217 no trata tus datos hasta que lo aceptes en la app.',
      );
  String get signInPrompt => _t(
        'Sign in to download your data, withdraw your consent or delete your account.',
        'Entre para baixar seus dados, revogar seu consentimento ou excluir sua conta.',
        'Inicia sesión para descargar tus datos, retirar tu consentimiento o eliminar tu cuenta.',
      );
  String get signInAction => _t('Sign in', 'Entrar', 'Iniciar sesión');
  String get signInUnavailable => _t(
        'Sign-in is not configured on this server; ask its operator to exercise your rights.',
        'O login não está configurado neste servidor; fale com quem o opera para exercer seus direitos.',
        'El inicio de sesión no está configurado en este servidor; pide a quien lo opera que atienda tus derechos.',
      );
  String get signInFailed => _t(
        'Could not start sign-in. Try again in a moment.',
        'Não foi possível iniciar o login. Tente de novo em instantes.',
        'No se pudo iniciar sesión. Inténtalo de nuevo en un momento.',
      );

  /// Native apps manage the data on the web page, in the browser.
  String get manageInBrowserBody => _t(
        'Download your data, withdraw your consent or delete your account on the web version of this page.',
        'Baixe seus dados, revogue seu consentimento ou exclua sua conta na versão web desta página.',
        'Descarga tus datos, retira tu consentimiento o elimina tu cuenta en la versión web de esta página.',
      );
  String get manageInBrowserAction => _t(
        'Open in the browser',
        'Abrir no navegador',
        'Abrir en el navegador',
      );

  String get downloadTitle =>
      _t('Download my data', 'Baixar meus dados', 'Descargar mis datos');
  String get downloadBody => _t(
        'Everything this server holds about you, as a JSON file.',
        'Tudo que este servidor guarda sobre você, em um arquivo JSON.',
        'Todo lo que este servidor guarda sobre ti, en un archivo JSON.',
      );
  String get downloadConfirmTitle =>
      _t('Download your data?', 'Baixar seus dados?', '¿Descargar tus datos?');
  String get downloadWarn => _t(
        'The file holds everything this server has about you, including sensitive health data. Keep it somewhere safe and do not share it.',
        'O arquivo traz tudo que este servidor tem sobre você, incluindo dados sensíveis de saúde. Guarde em um lugar seguro e não compartilhe.',
        'El archivo contiene todo lo que este servidor tiene sobre ti, incluidos datos sensibles de salud. Guárdalo en un lugar seguro y no lo compartas.',
      );
  String get downloadConfirm => _t('Download', 'Baixar', 'Descargar');
  String get downloadFailed => _t(
        'Could not download your data. Try again.',
        'Não foi possível baixar seus dados. Tente de novo.',
        'No se pudieron descargar tus datos. Inténtalo de nuevo.',
      );

  String get withdrawTitle =>
      _t('Withdraw consent', 'Revogar consentimento', 'Retirar consentimiento');
  String get withdrawBody => _t(
        'Stop agreeing to this notice. Your data is kept, but 217 stops processing it.',
        'Deixe de concordar com este aviso. Seus dados são mantidos, mas o 217 para de tratá-los.',
        'Deja de aceptar este aviso. Tus datos se conservan, pero 217 deja de tratarlos.',
      );
  String get withdrawConfirmTitle => _t('Withdraw your consent?',
      'Revogar seu consentimento?', '¿Retirar tu consentimiento?');
  String get withdrawWarn => _t(
        '217 will stop working for you: the app will not show or save your calendar, reminders, sharing or messages until you agree to the notice again. A partner following your calendar loses access too. Your data is not deleted; to erase it, delete your account.',
        'O 217 vai parar de funcionar para você: o app não vai mostrar nem salvar seu calendário, lembretes, compartilhamento ou mensagens até você concordar com o aviso de novo. Um parceiro que acompanha seu calendário também perde o acesso. Seus dados não são apagados; para apagá-los, exclua sua conta.',
        '217 dejará de funcionar para ti: la app no mostrará ni guardará tu calendario, recordatorios, uso compartido ni mensajes hasta que vuelvas a aceptar el aviso. Una pareja que sigue tu calendario también pierde el acceso. Tus datos no se eliminan; para borrarlos, elimina tu cuenta.',
      );
  String get withdrawFailed => _t(
        'Could not withdraw consent. Try again.',
        'Não foi possível revogar o consentimento. Tente de novo.',
        'No se pudo retirar el consentimiento. Inténtalo de nuevo.',
      );

  String get deleteTitle =>
      _t('Delete account', 'Excluir conta', 'Eliminar cuenta');
  String get deleteBody => _t(
        'Erase your account and everything in it from this server.',
        'Apague sua conta e tudo nela deste servidor.',
        'Borra tu cuenta y todo su contenido de este servidor.',
      );
  String get deleteConfirmTitle =>
      _t('Delete your account?', 'Excluir sua conta?', '¿Eliminar tu cuenta?');
  String deleteWarn(bool deletesLogin) => deletesLogin
      ? _t(
          'You will lose everything: your calendar, notes, messages, reminders and sharing are permanently deleted, along with your WorkOS sign-in identity. This cannot be undone.',
          'Você vai perder tudo: seu calendário, notas, mensagens, lembretes e compartilhamento são apagados permanentemente, junto com sua identidade de login da WorkOS. Não dá para desfazer.',
          'Lo perderás todo: tu calendario, notas, mensajes, recordatorios y uso compartido se eliminan permanentemente, junto con tu identidad de inicio de sesión de WorkOS. No se puede deshacer.',
        )
      : _t(
          'You will lose everything: your calendar, notes, messages, reminders and sharing are permanently deleted from this server. Your WorkOS sign-in identity remains. This cannot be undone.',
          'Você vai perder tudo: seu calendário, notas, mensagens, lembretes e compartilhamento são apagados permanentemente deste servidor. Sua identidade de login da WorkOS permanece. Não dá para desfazer.',
          'Lo perderás todo: tu calendario, notas, mensajes, recordatorios y uso compartido se eliminan permanentemente de este servidor. Tu identidad de inicio de sesión de WorkOS permanece. No se puede deshacer.',
        );
  String get deleteConfirm => _t('Delete permanently',
      'Excluir definitivamente', 'Eliminar definitivamente');
  String get deleteFailed => _t(
        'Could not delete the account; nothing was deleted. Try again.',
        'Não foi possível excluir a conta; nada foi apagado. Tente de novo.',
        'No se pudo eliminar la cuenta; no se borró nada. Inténtalo de nuevo.',
      );

  String get doneDeleted => _t(
        'Your account and data were deleted.',
        'Sua conta e seus dados foram excluídos.',
        'Tu cuenta y tus datos fueron eliminados.',
      );
  String get doneWithdrawn => _t(
        'Consent withdrawn. 217 will ask you to agree again the next time you open it.',
        'Consentimento revogado. O 217 vai pedir que você concorde de novo na próxima vez que abrir.',
        'Consentimiento retirado. 217 te pedirá aceptar de nuevo la próxima vez que lo abras.',
      );

  String get reauthAction => _t(
        'Sign in again to continue',
        'Entrar de novo para continuar',
        'Inicia sesión de nuevo para continuar',
      );
  String get reauthNote => _t(
        'To protect your data, confirm it is you by signing in again. You come back here to finish.',
        'Para proteger seus dados, confirme que é você entrando de novo. Você volta aqui para concluir.',
        'Para proteger tus datos, confirma que eres tú iniciando sesión de nuevo. Vuelves aquí para terminar.',
      );

  String get openApp => _t('Open 217', 'Abrir o 217', 'Abrir 217');

  // Account deletion page (/app/account/delete), linked from the store
  // listing: the steps, what is deleted and what is kept.

  String get deletePageTitle => _t(
        'Delete your 217 account',
        'Excluir sua conta do 217',
        'Eliminar tu cuenta de 217',
      );
  String get deletePageIntro => _t(
        'How to delete your account in 217, the pill calendar app, and which data goes with it.',
        'Como excluir sua conta no 217, o app de calendário do anticoncepcional, e quais dados vão junto.',
        'Cómo eliminar tu cuenta en 217, la app de calendario del anticonceptivo, y qué datos se van con ella.',
      );
  String get deleteStepsTitle => _t('How to delete your account',
      'Como excluir sua conta', 'Cómo eliminar tu cuenta');
  String get deleteStepApp => _t(
        'In the 217 app: open Settings, tap Advanced options, then Delete account, and confirm.',
        'No app 217: abra Ajustes, toque em Opções avançadas, depois em Excluir conta, e confirme.',
        'En la app 217: abre Ajustes, toca Opciones avanzadas, luego Eliminar cuenta, y confirma.',
      );
  String get deleteStepWeb => _t(
        'Or on this page: sign in below with the same account, tap Delete account, and confirm.',
        'Ou nesta página: entre abaixo com a mesma conta, toque em Excluir conta, e confirme.',
        'O en esta página: inicia sesión abajo con la misma cuenta, toca Eliminar cuenta, y confirma.',
      );
  String deleteStepContact(String contact) => _t(
        'Cannot sign in? Ask for the deletion at $contact.',
        'Não consegue entrar? Peça a exclusão em $contact.',
        '¿No puedes iniciar sesión? Pide la eliminación en $contact.',
      );
  String get deleteStepNoContact => _t(
        'Cannot sign in? Ask whoever runs this server to delete it.',
        'Não consegue entrar? Peça a exclusão a quem opera este servidor.',
        '¿No puedes iniciar sesión? Pide la eliminación a quien opera este servidor.',
      );
  String get deletedDataTitle =>
      _t('What is deleted', 'O que é apagado', 'Qué se elimina');
  String get deletedDataBody => _t(
        'Right away and permanently: your account, calendar entries (pill days, notes, intimacy and period days), birth month and reproductive stage, display name, the messages between you and your partner, reminder and alert settings, invites and sharing, and your sign-in sessions on every device. A partner following your calendar loses access.',
        'Na hora e para sempre: sua conta, os registros do calendário (dias do anticoncepcional, notas, dias de relação e de menstruação), mês de nascimento e fase reprodutiva, nome de exibição, as mensagens entre você e seu parceiro, os lembretes e alertas, convites e compartilhamento, e suas sessões em todos os aparelhos. Um parceiro que acompanha seu calendário perde o acesso.',
        'De inmediato y para siempre: tu cuenta, los registros del calendario (días del anticonceptivo, notas, días de relaciones y de regla), mes de nacimiento y etapa reproductiva, nombre visible, los mensajes entre tú y tu pareja, los recordatorios y alertas, invitaciones y uso compartido, y tus sesiones en todos los dispositivos. Una pareja que sigue tu calendario pierde el acceso.',
      );
  String get keptDataTitle =>
      _t('What is kept', 'O que é mantido', 'Qué se conserva');
  String keptDataBody(bool deletesLogin) => deletesLogin
      ? _t(
          'Nothing. Your WorkOS sign-in identity is deleted too, and 217 keeps no copy afterwards: there is no extra retention period.',
          'Nada. Sua identidade de login da WorkOS também é apagada, e o 217 não guarda cópia depois: não há prazo extra de retenção.',
          'Nada. Tu identidad de inicio de sesión de WorkOS también se elimina, y 217 no guarda ninguna copia después: no hay plazo extra de conservación.',
        )
      : _t(
          'Only your WorkOS sign-in identity (the email and name you sign in with), which this server cannot remove; ask its operator to. 217 keeps no copy of your data afterwards: there is no extra retention period.',
          'Só sua identidade de login da WorkOS (o email e o nome com que você entra), que este servidor não consegue remover; peça a quem o opera. O 217 não guarda cópia dos seus dados depois: não há prazo extra de retenção.',
          'Solo tu identidad de inicio de sesión de WorkOS (el email y el nombre con que inicias sesión), que este servidor no puede eliminar; pídeselo a quien lo opera. 217 no guarda copia de tus datos después: no hay plazo extra de conservación.',
        );
  String get privacyNoticeLink => _t(
        'Read the full privacy notice',
        'Leia o aviso de privacidade completo',
        'Lee el aviso de privacidad completo',
      );
}
