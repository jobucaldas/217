use dioxus::prelude::*;

use crate::api;
use crate::i18n::{t, Lang};
use crate::models::{AuthState, PwaStatus, ReminderPreference, VapidConfig};
use crate::pwa;

#[component]
pub fn ReminderSettings() -> Element {
    let mut auth = use_context::<Signal<AuthState>>();
    let language = use_context::<Signal<Lang>>();
    let mut preference = use_signal(ReminderPreference::default);
    let mut vapid = use_signal(|| VapidConfig {
        configured: false,
        public_key: String::new(),
    });
    let mut browser = use_signal(|| None::<PwaStatus>);
    let mut loading = use_signal(|| true);
    let mut pending = use_signal(|| false);
    let mut message = use_signal(String::new);
    let mut error = use_signal(String::new);
    let mut loaded = use_signal(|| false);
    let txt = t(&language());

    use_effect(move || {
        if loaded() {
            return;
        }
        loaded.set(true);
        spawn(async move {
            match api::get_reminder_preference().await {
                Ok(value) => preference.set(value),
                Err(error) if error.contains("401") => auth.set(AuthState::LoggedOut),
                Err(_) => {}
            }
            match api::get_vapid_config().await {
                Ok(value) => vapid.set(value),
                Err(error) if error.contains("401") => auth.set(AuthState::LoggedOut),
                Err(_) => {}
            }
            browser.set(pwa::status().await.ok());
            loading.set(false);
        });
    });

    let save_schedule = move |_| {
        if pending() {
            return;
        }
        pending.set(true);
        error.set(String::new());
        message.set(String::new());
        let value = preference();
        spawn(async move {
            match api::save_reminder_preference(&value).await {
                Ok(saved) => {
                    preference.set(saved);
                    message.set(t(&language()).reminder_saved.into());
                }
                Err(reason) if reason.contains("401") => auth.set(AuthState::LoggedOut),
                Err(_) => error.set(t(&language()).reminder_not_ready.into()),
            }
            pending.set(false);
        });
    };

    let enable = move |_| {
        if pending() {
            return;
        }
        pending.set(true);
        error.set(String::new());
        message.set(String::new());
        let public_key = vapid().public_key;
        let mut desired = preference();
        desired.enabled = true;
        desired.timezone = pwa::timezone();
        spawn(async move {
            let result = async {
                let subscription = pwa::subscribe(&public_key).await?;
                api::save_push_subscription(&subscription).await?;
                let saved = api::save_reminder_preference(&desired).await?;
                Ok::<_, String>(saved)
            }
            .await;
            match result {
                Ok(saved) => {
                    preference.set(saved);
                    browser.set(pwa::status().await.ok());
                    message.set(t(&language()).reminder_ready.into());
                }
                Err(reason) => {
                    let text = if reason.contains("permission-denied") {
                        t(&language()).permission_denied
                    } else if reason.contains("insecure-context") {
                        t(&language()).insecure_context
                    } else if reason.contains("401") {
                        auth.set(AuthState::LoggedOut);
                        t(&language()).session_expired
                    } else {
                        t(&language()).reminder_not_ready
                    };
                    error.set(text.into());
                    browser.set(pwa::status().await.ok());
                }
            }
            pending.set(false);
        });
    };

    let disable = move |_| {
        if pending() {
            return;
        }
        pending.set(true);
        error.set(String::new());
        let mut desired = preference();
        desired.enabled = false;
        spawn(async move {
            match api::save_reminder_preference(&desired).await {
                Ok(saved) => {
                    preference.set(saved);
                    match pwa::unsubscribe().await {
                        Ok(endpoint) if !endpoint.is_empty() => {
                            if api::delete_push_subscription(&endpoint).await.is_err() {
                                error.set(t(&language()).reminder_not_ready.into());
                            }
                        }
                        Ok(_) => {}
                        Err(_) => error.set(t(&language()).reminder_not_ready.into()),
                    }
                    browser.set(pwa::status().await.ok());
                }
                Err(reason) if reason.contains("401") => auth.set(AuthState::LoggedOut),
                Err(_) => error.set(t(&language()).reminder_not_ready.into()),
            }
            pending.set(false);
        });
    };

    rsx! {
        section { style: "display:grid;gap:10px;",
            h4 { style: "margin:4px 0;", "{txt.reminder_settings}" }
            if loading() { p { class: "muted", "{txt.loading}" } } else {
                div { class: "field",
                    label { r#for: "reminder-time", "{txt.reminder_time}" }
                    input { id: "reminder-time", r#type: "time", value: "{preference().time}", disabled: pending(), oninput: move |event| preference.write().time = event.value() }
                }
                p { class: "muted", style: "margin:0;font-size:13px;", "{txt.timezone}: {preference().timezone}" }
                if !vapid().configured {
                    p { class: "error", role: "status", "{txt.push_unconfigured}" }
                } else if let Some(status) = browser() {
                    if !status.secure { p { class: "error", role: "status", "{txt.insecure_context}" } }
                    else if !status.supported { p { class: "error", role: "status", "{txt.push_unsupported}" } }
                    else if status.permission == "denied" { p { class: "error", role: "status", "{txt.permission_denied} {txt.permission_help}" } }
                    else if preference().deliverable && status.subscribed { p { class: "success", role: "status", "{txt.reminder_ready}" } }
                    else { p { class: "muted", role: "status", "{txt.reminder_not_ready}" } }
                    if status.installable && !status.standalone {
                        button { class: "secondary", disabled: pending(), onclick: move |_| { spawn(async move { let _ = pwa::install().await; browser.set(pwa::status().await.ok()); }); }, "{txt.install_app}" }
                    }
                }
                div { style: "display:grid;gap:8px;",
                    button { class: "secondary", disabled: pending(), onclick: save_schedule, "{txt.save}" }
                    if preference().enabled {
                        button { class: "primary", disabled: pending(), onclick: disable, "{txt.disable_reminders}" }
                    } else {
                        button { class: "primary", disabled: pending() || !vapid().configured, onclick: enable, "{txt.enable_reminders}" }
                    }
                }
                if !message().is_empty() { p { class: "success", role: "status", "{message}" } }
                if !error().is_empty() { p { class: "error", role: "alert", "{error}" } }
            }
        }
    }
}
