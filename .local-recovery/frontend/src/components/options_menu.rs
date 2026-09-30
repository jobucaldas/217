use dioxus::prelude::*;

use crate::api;
use crate::i18n::{t, Lang};
use crate::models::AuthState;
use crate::pwa;

#[component]
pub fn OptionsMenu() -> Element {
    let auth = use_context::<Signal<AuthState>>();
    let language = use_context::<Signal<Lang>>();
    let mut open = use_signal(|| false);
    let mut pending = use_signal(|| false);
    let mut logout_error = use_signal(|| false);
    let txt = t(&language());

    let logout = move |_| {
        if pending() {
            return;
        }
        pending.set(true);
        logout_error.set(false);
        let mut auth = auth;
        let mut open = open;
        spawn(async move {
            if let Ok(endpoint) = pwa::unsubscribe().await {
                if !endpoint.is_empty() {
                    let _ = api::delete_push_subscription(&endpoint).await;
                }
            }
            if api::logout().await.is_ok() {
                auth.set(AuthState::LoggedOut);
                open.set(false);
            } else {
                logout_error.set(true);
            }
            pending.set(false);
        });
    };

    rsx! {
        div { style: "position:relative;",
            button { class: "secondary", aria_label: "{txt.options}", aria_expanded: open(), onclick: move |_| open.set(!open()), "☰" }
            if open() {
                aside { class: "card", style: "position:absolute;right:0;top:50px;width:min(340px,calc(100vw - 20px));max-height:calc(100dvh - 70px);overflow:auto;z-index:100;box-shadow:0 10px 30px #0005;",
                    if logout_error() {
                        p { class: "error", role: "alert", "{txt.logout_failed}" }
                    }
                    button { class: "primary", style: "width:100%;background:var(--danger);", disabled: pending(), onclick: logout, "{txt.logout}" }
                }
            }
        }
    }
}
