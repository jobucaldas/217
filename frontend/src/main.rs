use chrono::{Datelike, NaiveDate};
use dioxus::prelude::*;
use std::collections::{HashMap, HashSet};

mod api;
mod components;
mod i18n;
mod models;
mod pwa;

use components::calendar::Calendar;
use components::day_modal::DayModal;
use components::options_menu::OptionsMenu;
use i18n::{t, Lang};
use models::{AuthState, Entry};

fn add_months(date: NaiveDate, n: i32) -> NaiveDate {
    let mut year = date.year();
    let mut month = date.month() as i32 + n;
    while month > 12 {
        month -= 12;
        year += 1;
    }
    while month < 1 {
        month += 12;
        year -= 1;
    }
    NaiveDate::from_ymd_opt(year, month as u32, 1).unwrap()
}

fn months_in_range(start: NaiveDate, end: NaiveDate) -> Vec<(i32, u32)> {
    let mut result = Vec::new();
    let mut current = start;
    while current <= end {
        result.push((current.year(), current.month()));
        current = add_months(current, 1);
    }
    result
}

fn current_user_id(auth: &AuthState) -> String {
    auth.user().map(|user| user.id.clone()).unwrap_or_default()
}

#[allow(non_snake_case)]
fn App() -> Element {
    use_context_provider(|| Signal::new(AuthState::Loading));
    use_context_provider(|| Signal::new(true));
    use_context_provider(|| Signal::new(Lang::Pt));

    let today = NaiveDate::parse_from_str(&pwa::local_date(), "%Y-%m-%d")
        .unwrap_or_else(|_| chrono::Local::now().date_naive());
    let current_month = NaiveDate::from_ymd_opt(today.year(), today.month(), 1).unwrap();
    let mut auth = use_context::<Signal<AuthState>>();
    let dark_mode = use_context::<Signal<bool>>();
    let language = use_context::<Signal<Lang>>();
    let mut month_start = use_signal(|| add_months(current_month, -6));
    let mut month_end = use_signal(|| add_months(current_month, 3));
    let mut entries_map = use_signal(HashMap::<String, Entry>::new);
    let mut loaded_months = use_signal(HashSet::<String>::new);
    let mut entries_owner = use_signal(String::new);
    let mut selected_day = use_signal(|| None::<(String, Option<bool>, String)>);
    let mut settings_open = use_signal(|| false);
    let mut saving = use_signal(|| false);
    let mut save_error = use_signal(String::new);
    let mut load_error = use_signal(String::new);
    let mut reload_nonce = use_signal(|| 0_u32);
    let mut reminder_summary = use_signal(String::new);

    use_effect(move || {
        spawn(async move {
            auth.set(match api::current_session().await {
                Ok(Some(user)) => AuthState::Authenticated { user },
                Ok(None) | Err(_) => AuthState::LoggedOut,
            });
        });
    });

    use_effect(move || {
        let lang = language();
        if let Some(document) = web_sys::window().and_then(|window| window.document()) {
            if let Some(root) = document.document_element() {
                let _ = root.set_attribute("lang", if lang == Lang::Pt { "pt-BR" } else { "en" });
            }
        }
    });

    use_effect(move || {
        let state = auth.read().clone();
        let user_id = current_user_id(&state);
        if entries_owner() != user_id {
            entries_map.write().clear();
            loaded_months.write().clear();
            selected_day.set(None);
            settings_open.set(false);
            saving.set(false);
            save_error.set(String::new());
            load_error.set(String::new());
            reminder_summary.set(String::new());
            entries_owner.set(user_id.clone());
        }
        if !state.is_authenticated() {
            return;
        }
        let _ = reload_nonce();
        let owner_for_request = user_id.clone();
        let to_load: Vec<_> = months_in_range(month_start(), month_end())
            .into_iter()
            .filter(|(year, month)| {
                !loaded_months
                    .read()
                    .contains(&format!("{year:04}-{month:02}"))
            })
            .collect();
        spawn(async move {
            if let Ok(preference) = api::get_reminder_preference().await {
                if entries_owner() == owner_for_request {
                    reminder_summary.set(if preference.deliverable {
                        format!(
                            "{} · {} · {}",
                            t(&language()).reminders_on,
                            preference.time,
                            preference.timezone
                        )
                    } else {
                        t(&language()).reminders_off.to_string()
                    });
                }
            }
            for (year, month) in to_load {
                match api::list_entries(year, month as i32).await {
                    Ok(data) if entries_owner() == owner_for_request => {
                        loaded_months
                            .write()
                            .insert(format!("{year:04}-{month:02}"));
                        for entry in data.entries {
                            entries_map.write().insert(entry.date.clone(), entry);
                        }
                        load_error.set(String::new());
                    }
                    Err(error) if entries_owner() == owner_for_request => {
                        load_error.set(t(&language()).load_error.to_string());
                        if error.contains("401") {
                            auth.set(AuthState::LoggedOut);
                        }
                    }
                    _ => {}
                }
            }
        });
    });

    use_effect(move || {
        if !auth.read().is_authenticated() {
            return;
        }
        let id = format!("month-{:04}-{:02}", today.year(), today.month());
        if let Some(element) = web_sys::window()
            .and_then(|window| window.document())
            .and_then(|document| document.get_element_by_id(&id))
        {
            element.scroll_into_view();
        }
    });

    let mut open_day = move |(date, status, notes): (String, Option<bool>, String)| {
        save_error.set(String::new());
        selected_day.set(Some((date, status, notes)));
    };

    let save_day = move |(taken, notes): (bool, String)| {
        if saving() {
            return;
        }
        let Some((date, _, _)) = selected_day() else {
            return;
        };
        let owner = current_user_id(&auth.read());
        saving.set(true);
        save_error.set(String::new());
        spawn(async move {
            match api::upsert_entry(&date, taken, &notes).await {
                Ok(entry) if entries_owner() == owner => {
                    entries_map.write().insert(entry.date.clone(), entry);
                    selected_day.set(None);
                }
                Err(error) => {
                    save_error.set(if error.contains("401") {
                        auth.set(AuthState::LoggedOut);
                        t(&language()).load_error.to_string()
                    } else {
                        t(&language()).load_error.to_string()
                    });
                }
                _ => {}
            }
            saving.set(false);
        });
    };

    let auth_snapshot = auth.read().clone();
    let user_id = current_user_id(&auth_snapshot);
    let visible_entries = if entries_owner() == user_id {
        entries_map()
    } else {
        HashMap::new()
    };
    let today_key = today.format("%Y-%m-%d").to_string();
    let today_entry = visible_entries.get(&today_key).cloned();
    let today_style = match today_entry.as_ref().map(|entry| entry.taken) {
        Some(true) => "background:var(--taken);color:white;",
        Some(false) => "background:var(--missed);color:white;",
        None => "background:var(--future);",
    };
    let txt = t(&language());
    let theme_class = if dark_mode() { "dark" } else { "light" };

    rsx! {
        div { class: "app {theme_class}",
            if auth_snapshot.is_loading() {
                main { class: "shell", p { class: "muted", "…" } }
            } else if !auth_snapshot.is_authenticated() {
                components::auth::AuthScreen {}
            } else {
                main { class: "shell",
                    header { class: "header",
                        h1 { style: "margin:0;font-size:24px;", "217" }
                        div { class: "status-row",
                            button { id: "open-settings", class: "secondary", aria_label: "{txt.settings}", aria_expanded: settings_open(), onclick: move |_| settings_open.set(true), "{txt.settings}" }
                            OptionsMenu {}
                        }
                    }
                    if settings_open() {
                        components::settings::Settings { on_back: move |_| { settings_open.set(false); reload_nonce.set(reload_nonce() + 1); } }
                    }
                    // Keep the calendar mounted so loaded months and scroll position survive.
                    div { style: if settings_open() { "display:none;" } else { "display:block;" },
                    section { class: "card today-card", aria_label: "{txt.today_status}",
                        div { class: "status-row",
                            strong { "{txt.today} · {today_key}" }
                            span { class: "pill", style: "{today_style}",
                                if let Some(entry) = &today_entry { if entry.taken { "{txt.taken}" } else { "{txt.not_taken}" } } else { "{txt.unrecorded}" }
                            }
                        }
                        p { class: "muted", style: "margin:0;font-size:13px;", if reminder_summary().is_empty() { "{txt.reminder_not_ready}" } else { "{reminder_summary}" } }
                        div { class: "status-row",
                            button { class: "secondary", onclick: move |_| open_day((today_key.clone(), today_entry.as_ref().map(|entry| entry.taken), today_entry.as_ref().map(|entry| entry.notes.clone()).unwrap_or_default())), "{txt.today_status}" }
                            button { class: "secondary", onclick: move |_| {
                                let id = format!("month-{:04}-{:02}", today.year(), today.month());
                                if let Some(element) = web_sys::window().and_then(|window| window.document()).and_then(|document| document.get_element_by_id(&id)) { element.scroll_into_view(); }
                            }, "{txt.today}" }
                        }
                    }
                    if !load_error().is_empty() {
                        div { class: "error", role: "alert", "{load_error}" button { class: "secondary", style: "margin-left:8px;", onclick: move |_| { load_error.set(String::new()); reload_nonce.set(reload_nonce() + 1); }, "{txt.retry}" } }
                    }
                    Calendar {
                        months: months_in_range(month_start(), month_end()),
                        entries: visible_entries,
                        today,
                        on_toggle: open_day,
                        on_scroll_more: move |(backward,)| if backward { month_start.set(add_months(month_start(), -6)); } else { month_end.set(add_months(month_end(), 6)); },
                    }
                    }
                }
            }
            if let Some((date, status, notes)) = selected_day() {
                DayModal { date_str: date, taken: status, notes, saving: saving(), save_error: save_error(), on_save: save_day, on_close: move |_| if !saving() { selected_day.set(None); } }
            }
        }
    }
}

fn main() {
    dioxus::launch(App);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn month_range_crosses_year_boundaries() {
        let start = NaiveDate::from_ymd_opt(2025, 11, 1).unwrap();
        let end = add_months(start, 3);
        assert_eq!(
            months_in_range(start, end),
            vec![(2025, 11), (2025, 12), (2026, 1), (2026, 2)]
        );
    }
}
