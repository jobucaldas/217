package handler

// privacyText is the privacy page wording in one language. The notice part
// mirrors what the app used to show inline (LGPD arts. 9, 11, 18).
type privacyText struct {
	LangName, LanguageLabel string
	Title, Intro            string

	SensitiveTitle, SensitiveBody string
	WhatTitle, WhatBody           string
	WhyTitle, WhyBody             string
	// WhereBody takes the server name (%s).
	WhereTitle, WhereBody           string
	RightsTitle, RightsBody         string
	ContactTitle, ContactNone       string
	YourDataTitle                   string
	SignedInAs, NoConsent           string
	SignInPrompt, SignInAction      string
	SignInUnavailable, SignInFailed string
	DownloadTitle, DownloadBody     string
	DownloadAction                  string
	DownloadConfirmTitle            string
	DownloadWarn, DownloadConfirm   string
	ReauthAction, ReauthNote        string
	WithdrawTitle, WithdrawBody     string
	WithdrawAction, WithdrawConfirm string
	WithdrawConfirmTitle            string
	WithdrawWarn, WithdrawFailed    string
	DeleteTitle, DeleteBody         string
	DeleteAction, DeleteConfirm     string
	DeleteConfirmTitle              string
	DeleteWarnDeletesLogin          string
	DeleteWarnKeepsLogin            string
	DeleteFailed                    string
	DoneDeleted, DoneWithdrawn      string
	Cancel, FormExpired             string
	SignedOutError                  string
}

var privacyTexts = map[string]privacyText{
	"en": {
		LangName:               "English",
		LanguageLabel:          "Language",
		Title:                  "Privacy notice",
		Intro:                  "What 217 stores about you, why, and what you can do about it.",
		SensitiveTitle:         "Sensitive health data",
		SensitiveBody:          "217 records when you take your contraceptive, missed days, notes, sex and period days. Under Brazil's LGPD (Law 13.709/2018) this is sensitive data about health and sex life, so it is only processed with your specific consent.",
		WhatTitle:              "What is stored",
		WhatBody:               "Your email and name from sign-in, the display name you choose (shown to your partner), your birth month and reproductive stage if you give them, your calendar entries, messages between you and your partner, and your reminder and alert times.",
		WhyTitle:               "Why",
		WhyBody:                "Only to show your calendar and stats, predict periods and PMS, suggest a reproductive stage from your age and period history, remind you, and share the calendar read-only with the one partner you invite. Never for ads or profiling, and never sold.",
		WhereTitle:             "Where and who sees it",
		WhereBody:              "On the server %s, run by its operator (the controller). It is encrypted in transit (TLS). Calendar entries, notes, names, display names, emails, birth month and reproductive stage are encrypted at rest with AES-256. Reminder times, alert times and operational timestamps are stored so the app can run and are not sealed. Only you and a partner you invite see your calendar. Sign-in is handled by WorkOS, which receives your email.",
		RightsTitle:            "Your rights",
		RightsBody:             "Correct any day or stop sharing in the app. On this page you can download all your data, withdraw your consent, or delete your account and everything in it, at any time.",
		ContactTitle:           "Contact",
		ContactNone:            "Ask whoever runs this server.",
		YourDataTitle:          "Your data",
		SignedInAs:             "Signed in as %s.",
		NoConsent:              "You have not agreed to this notice, so 217 does not process your data until you agree in the app.",
		SignInPrompt:           "Sign in to download your data, withdraw your consent or delete your account.",
		SignInAction:           "Sign in",
		SignInUnavailable:      "Sign-in is not configured on this server; ask its operator to exercise your rights.",
		SignInFailed:           "Could not start sign-in. Try again in a moment.",
		DownloadTitle:          "Download my data",
		DownloadBody:           "Everything this server holds about you, as a JSON file.",
		DownloadAction:         "Download my data",
		WithdrawTitle:          "Withdraw consent",
		WithdrawBody:           "Stop agreeing to this notice. Your data is kept, but 217 stops processing it.",
		WithdrawAction:         "Withdraw consent",
		WithdrawConfirmTitle:   "Withdraw your consent?",
		WithdrawWarn:           "217 will stop working for you: the app will not show or save your calendar, reminders, sharing or messages until you agree to the notice again. A partner following your calendar loses access too. Your data is not deleted; to erase it, delete your account.",
		WithdrawConfirm:        "Withdraw consent",
		WithdrawFailed:         "Could not withdraw consent. Try again.",
		DeleteTitle:            "Delete account",
		DeleteBody:             "Erase your account and everything in it from this server.",
		DeleteAction:           "Delete account",
		DeleteConfirmTitle:     "Delete your account?",
		DeleteWarnDeletesLogin: "You will lose everything: your calendar, notes, messages, reminders and sharing are permanently deleted, along with your WorkOS sign-in identity. This cannot be undone.",
		DeleteWarnKeepsLogin:   "You will lose everything: your calendar, notes, messages, reminders and sharing are permanently deleted from this server. Your WorkOS sign-in identity remains. This cannot be undone.",
		DeleteConfirm:          "Delete permanently",
		DeleteFailed:           "Could not delete the account; nothing was deleted. Try again.",
		DoneDeleted:            "Your account and data were deleted.",
		DoneWithdrawn:          "Consent withdrawn. 217 will ask you to agree again the next time you open it.",
		Cancel:                 "Cancel",
		FormExpired:            "This page expired. Reload it and try again.",
		SignedOutError:         "You are signed out. Sign in and try again.",
		DownloadConfirmTitle:   "Download your data?",
		DownloadWarn:           "The file holds everything this server has about you, including sensitive health data. Keep it somewhere safe and do not share it.",
		DownloadConfirm:        "Download",
		ReauthAction:           "Sign in again to continue",
		ReauthNote:             "To protect your data, confirm it is you by signing in again. You come back here to finish.",
	},
	"pt": {
		LangName:               "Português",
		LanguageLabel:          "Idioma",
		Title:                  "Aviso de privacidade",
		Intro:                  "O que o 217 guarda sobre você, para quê, e o que você pode fazer.",
		SensitiveTitle:         "Dados sensíveis de saúde",
		SensitiveBody:          "217 registra quando você toma o anticoncepcional, dias esquecidos, notas, sexo e dias de menstruação. Pela LGPD (Lei 13.709/2018) são dados sensíveis de saúde e vida sexual, por isso só são tratados com o seu consentimento específico.",
		WhatTitle:              "O que é guardado",
		WhatBody:               "Seu email e nome do login, o nome de exibição que você escolher (mostrado ao parceiro), seu mês de nascimento e fase reprodutiva se você informar, os registros do calendário, as mensagens entre você e seu parceiro, e os horários de lembretes e alertas.",
		WhyTitle:               "Para quê",
		WhyBody:                "Só para mostrar seu calendário e estatísticas, prever menstruação e TPM, sugerir uma fase reprodutiva pela sua idade e histórico de menstruação, lembrar você e compartilhar o calendário, só para leitura, com o parceiro que você convidar. Nunca para anúncios ou perfilamento, e nunca vendidos.",
		WhereTitle:             "Onde fica e quem vê",
		WhereBody:              "No servidor %s, mantido por quem o opera (o controlador). Fica criptografado em trânsito (TLS). Registros do calendário, notas, nomes, nomes de exibição, emails, mês de nascimento e fase reprodutiva são criptografados em repouso com AES-256. Horários de lembretes e alertas e registros operacionais são guardados para o app funcionar e não são selados. Só você e o parceiro que você convidar veem seu calendário. O login é feito pela WorkOS, que recebe seu email.",
		RightsTitle:            "Seus direitos",
		RightsBody:             "Corrija qualquer dia ou pare de compartilhar no app. Nesta página você pode baixar todos os seus dados, revogar seu consentimento ou excluir sua conta e tudo nela, quando quiser.",
		ContactTitle:           "Contato",
		ContactNone:            "Fale com quem opera este servidor.",
		YourDataTitle:          "Seus dados",
		SignedInAs:             "Conectado como %s.",
		NoConsent:              "Você não concordou com este aviso, então o 217 não trata seus dados até você concordar no app.",
		SignInPrompt:           "Entre para baixar seus dados, revogar seu consentimento ou excluir sua conta.",
		SignInAction:           "Entrar",
		SignInUnavailable:      "O login não está configurado neste servidor; fale com quem o opera para exercer seus direitos.",
		SignInFailed:           "Não foi possível iniciar o login. Tente de novo em instantes.",
		DownloadTitle:          "Baixar meus dados",
		DownloadBody:           "Tudo que este servidor guarda sobre você, em um arquivo JSON.",
		DownloadAction:         "Baixar meus dados",
		WithdrawTitle:          "Revogar consentimento",
		WithdrawBody:           "Deixe de concordar com este aviso. Seus dados são mantidos, mas o 217 para de tratá-los.",
		WithdrawAction:         "Revogar consentimento",
		WithdrawConfirmTitle:   "Revogar seu consentimento?",
		WithdrawWarn:           "O 217 vai parar de funcionar para você: o app não vai mostrar nem salvar seu calendário, lembretes, compartilhamento ou mensagens até você concordar com o aviso de novo. Um parceiro que acompanha seu calendário também perde o acesso. Seus dados não são apagados; para apagá-los, exclua sua conta.",
		WithdrawConfirm:        "Revogar consentimento",
		WithdrawFailed:         "Não foi possível revogar o consentimento. Tente de novo.",
		DeleteTitle:            "Excluir conta",
		DeleteBody:             "Apague sua conta e tudo nela deste servidor.",
		DeleteAction:           "Excluir conta",
		DeleteConfirmTitle:     "Excluir sua conta?",
		DeleteWarnDeletesLogin: "Você vai perder tudo: seu calendário, notas, mensagens, lembretes e compartilhamento são apagados permanentemente, junto com sua identidade de login da WorkOS. Não dá para desfazer.",
		DeleteWarnKeepsLogin:   "Você vai perder tudo: seu calendário, notas, mensagens, lembretes e compartilhamento são apagados permanentemente deste servidor. Sua identidade de login da WorkOS permanece. Não dá para desfazer.",
		DeleteConfirm:          "Excluir definitivamente",
		DeleteFailed:           "Não foi possível excluir a conta; nada foi apagado. Tente de novo.",
		DoneDeleted:            "Sua conta e seus dados foram excluídos.",
		DoneWithdrawn:          "Consentimento revogado. O 217 vai pedir que você concorde de novo na próxima vez que abrir.",
		Cancel:                 "Cancelar",
		FormExpired:            "Esta página expirou. Recarregue e tente de novo.",
		SignedOutError:         "Você saiu da conta. Entre e tente de novo.",
		DownloadConfirmTitle:   "Baixar seus dados?",
		DownloadWarn:           "O arquivo traz tudo que este servidor tem sobre você, incluindo dados sensíveis de saúde. Guarde em um lugar seguro e não compartilhe.",
		DownloadConfirm:        "Baixar",
		ReauthAction:           "Entrar de novo para continuar",
		ReauthNote:             "Para proteger seus dados, confirme que é você entrando de novo. Você volta aqui para concluir.",
	},
	"es": {
		LangName:               "Español",
		LanguageLabel:          "Idioma",
		Title:                  "Aviso de privacidad",
		Intro:                  "Qué guarda 217 sobre ti, para qué y qué puedes hacer al respecto.",
		SensitiveTitle:         "Datos sensibles de salud",
		SensitiveBody:          "217 registra cuándo tomas el anticonceptivo, días olvidados, notas, sexo y días de regla. Según la LGPD de Brasil (Ley 13.709/2018) son datos sensibles de salud y vida sexual, por eso solo se tratan con tu consentimiento específico.",
		WhatTitle:              "Qué se guarda",
		WhatBody:               "Tu email y nombre del inicio de sesión, el nombre visible que elijas (lo ve tu pareja), tu mes de nacimiento y etapa reproductiva si los indicas, los registros del calendario, los mensajes entre tú y tu pareja, y las horas de recordatorios y alertas.",
		WhyTitle:               "Para qué",
		WhyBody:                "Solo para mostrar tu calendario y estadísticas, predecir la regla y el SPM, sugerir una etapa reproductiva según tu edad e historial de reglas, recordarte y compartir el calendario, solo lectura, con la pareja que invites. Nunca para anuncios o perfiles, y nunca se venden.",
		WhereTitle:             "Dónde está y quién lo ve",
		WhereBody:              "En el servidor %s, gestionado por quien lo opera (el responsable). Está cifrado en tránsito (TLS). Las entradas del calendario, notas, nombres, nombres visibles, correos, mes de nacimiento y etapa reproductiva están cifrados en reposo con AES-256. Las horas de recordatorios y alertas y las marcas operativas se guardan para que funcione la app y no están selladas. Solo tú y la pareja que invites ven tu calendario. El inicio de sesión lo hace WorkOS, que recibe tu email.",
		RightsTitle:            "Tus derechos",
		RightsBody:             "Corrige cualquier día o deja de compartir en la app. En esta página puedes descargar todos tus datos, retirar tu consentimiento o eliminar tu cuenta y todo su contenido, cuando quieras.",
		ContactTitle:           "Contacto",
		ContactNone:            "Pregunta a quien opera este servidor.",
		YourDataTitle:          "Tus datos",
		SignedInAs:             "Sesión iniciada como %s.",
		NoConsent:              "No has aceptado este aviso, así que 217 no trata tus datos hasta que lo aceptes en la app.",
		SignInPrompt:           "Inicia sesión para descargar tus datos, retirar tu consentimiento o eliminar tu cuenta.",
		SignInAction:           "Iniciar sesión",
		SignInUnavailable:      "El inicio de sesión no está configurado en este servidor; pide a quien lo opera que atienda tus derechos.",
		SignInFailed:           "No se pudo iniciar sesión. Inténtalo de nuevo en un momento.",
		DownloadTitle:          "Descargar mis datos",
		DownloadBody:           "Todo lo que este servidor guarda sobre ti, en un archivo JSON.",
		DownloadAction:         "Descargar mis datos",
		WithdrawTitle:          "Retirar consentimiento",
		WithdrawBody:           "Deja de aceptar este aviso. Tus datos se conservan, pero 217 deja de tratarlos.",
		WithdrawAction:         "Retirar consentimiento",
		WithdrawConfirmTitle:   "¿Retirar tu consentimiento?",
		WithdrawWarn:           "217 dejará de funcionar para ti: la app no mostrará ni guardará tu calendario, recordatorios, uso compartido ni mensajes hasta que vuelvas a aceptar el aviso. Una pareja que sigue tu calendario también pierde el acceso. Tus datos no se eliminan; para borrarlos, elimina tu cuenta.",
		WithdrawConfirm:        "Retirar consentimiento",
		WithdrawFailed:         "No se pudo retirar el consentimiento. Inténtalo de nuevo.",
		DeleteTitle:            "Eliminar cuenta",
		DeleteBody:             "Borra tu cuenta y todo su contenido de este servidor.",
		DeleteAction:           "Eliminar cuenta",
		DeleteConfirmTitle:     "¿Eliminar tu cuenta?",
		DeleteWarnDeletesLogin: "Lo perderás todo: tu calendario, notas, mensajes, recordatorios y uso compartido se eliminan permanentemente, junto con tu identidad de inicio de sesión de WorkOS. No se puede deshacer.",
		DeleteWarnKeepsLogin:   "Lo perderás todo: tu calendario, notas, mensajes, recordatorios y uso compartido se eliminan permanentemente de este servidor. Tu identidad de inicio de sesión de WorkOS permanece. No se puede deshacer.",
		DeleteConfirm:          "Eliminar definitivamente",
		DeleteFailed:           "No se pudo eliminar la cuenta; no se borró nada. Inténtalo de nuevo.",
		DoneDeleted:            "Tu cuenta y tus datos fueron eliminados.",
		DoneWithdrawn:          "Consentimiento retirado. 217 te pedirá aceptar de nuevo la próxima vez que lo abras.",
		Cancel:                 "Cancelar",
		FormExpired:            "Esta página caducó. Recárgala e inténtalo de nuevo.",
		SignedOutError:         "Cerraste sesión. Inicia sesión e inténtalo de nuevo.",
		DownloadConfirmTitle:   "¿Descargar tus datos?",
		DownloadWarn:           "El archivo contiene todo lo que este servidor tiene sobre ti, incluidos datos sensibles de salud. Guárdalo en un lugar seguro y no lo compartas.",
		DownloadConfirm:        "Descargar",
		ReauthAction:           "Inicia sesión de nuevo para continuar",
		ReauthNote:             "Para proteger tus datos, confirma que eres tú iniciando sesión de nuevo. Vuelves aquí para terminar.",
	},
}
