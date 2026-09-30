use dioxus::prelude::*;

use crate::components::reminder_settings::ReminderSettings;
use crate::i18n::{t, Lang};

#[component]
pub fn Settings(on_back: EventHandler<()>) -> Element {
    let mut dark_mode = use_context::<Signal<bool>>();
    let mut language = use_context::<Signal<Lang>>();
    let txt = t(&language());

    rsx! {
        section { class: "card settings-screen", aria_label: "{txt.settings}",
            button { class: "secondary", onclick: move |_| on_back.call(()), "← {txt.back_calendar}" }
            h2 { style: "margin:0;", "{txt.settings}" }
            div { class: "status-row",
                span { "{txt.dark_mode}" }
                button { class: "secondary", onclick: move |_| dark_mode.set(!dark_mode()), if dark_mode() { "{txt.light_mode}" } else { "{txt.dark_mode}" } }
            }
            div { class: "status-row",
                span { "{txt.language}" }
                button { class: "secondary", onclick: move |_| language.set(if language() == Lang::Pt { Lang::En } else { Lang::Pt }), if language() == Lang::Pt { "English" } else { "Português" } }
            }
            ReminderSettings {}
        }
    }
}
