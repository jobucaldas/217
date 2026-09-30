use dioxus::prelude::*;

use crate::i18n::{t, Lang};

#[derive(Props, Clone, PartialEq)]
pub struct DayModalProps {
    pub date_str: String,
    pub taken: Option<bool>,
    pub notes: String,
    pub saving: bool,
    pub save_error: String,
    pub on_save: EventHandler<(bool, String)>,
    pub on_close: EventHandler<()>,
}

#[component]
pub fn DayModal(props: DayModalProps) -> Element {
    let language = use_context::<Signal<Lang>>();
    let txt = t(&language());
    let mut taken = use_signal(|| props.taken);
    let mut notes = use_signal(|| props.notes.clone());
    let status_text = match taken() {
        Some(true) => txt.taken,
        Some(false) => txt.not_taken,
        None => txt.unrecorded,
    };
    let status_bg = match taken() {
        Some(true) => "var(--taken)",
        Some(false) => "var(--missed)",
        None => "var(--future)",
    };

    rsx! {
        div { class: "modal-overlay", onclick: move |_| if !props.saving { props.on_close.call(()) },
            div { class: "modal-card", role: "dialog", aria_modal: "true", aria_labelledby: "day-dialog-title", tabindex: "-1",
                onkeydown: move |event| if event.key() == Key::Escape && !props.saving { props.on_close.call(()) },
                onclick: move |event| event.stop_propagation(),
                div { style: "display:flex;justify-content:space-between;align-items:center;gap:8px;",
                    h2 { id: "day-dialog-title", style: "margin:0;font-size:20px;", "{props.date_str}" }
                    button { class: "secondary", aria_label: "{txt.close}", disabled: props.saving, onclick: move |_| props.on_close.call(()), "×" }
                }
                div { role: "status", style: "text-align:center;padding:12px;margin:14px 0;border-radius:10px;background:{status_bg};color:white;font-weight:800;", "{status_text}" }
                div { style: "display:flex;gap:8px;margin-bottom:14px;",
                    button { class: "secondary", style: if taken() == Some(true) { "flex:1;background:var(--taken);color:white;border-color:var(--taken);" } else { "flex:1;" }, disabled: props.saving, onclick: move |_| taken.set(Some(true)), "{txt.taken_label}" }
                    button { class: "secondary", style: if taken() == Some(false) { "flex:1;background:var(--missed);color:white;border-color:var(--missed);" } else { "flex:1;" }, disabled: props.saving, onclick: move |_| taken.set(Some(false)), "{txt.missed_label}" }
                }
                div { class: "field",
                    label { r#for: "day-notes", "{txt.notes_label}" }
                    textarea { id: "day-notes", rows: 4, placeholder: "{txt.notes_ph}", value: "{notes}", disabled: props.saving, oninput: move |event| notes.set(event.value()) }
                }
                if taken().is_none() { p { class: "muted", role: "status", "{txt.select_status}" } }
                if !props.save_error.is_empty() { p { class: "error", role: "alert", "{props.save_error}" } }
                div { style: "display:flex;gap:8px;margin-top:14px;",
                    button { class: "secondary", style: "flex:1;", disabled: props.saving, onclick: move |_| props.on_close.call(()), "{txt.cancel}" }
                    button { class: "primary", style: "flex:1;", disabled: props.saving || taken().is_none(), onclick: move |_| if let Some(value) = taken() { props.on_save.call((value, notes())) },
                        if props.saving { "{txt.saving}" } else if props.save_error.is_empty() { "{txt.save}" } else { "{txt.retry}" }
                    }
                }
            }
        }
    }
}
