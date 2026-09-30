use dioxus::prelude::*;

use crate::i18n::{t, Lang};

#[component]
pub fn AuthScreen() -> Element {
    let mut language = use_context::<Signal<Lang>>();
    let txt = t(&language());

    rsx! {
        main { class: "shell", style: "max-width:390px;padding-top:max(32px,env(safe-area-inset-top));",
            div { style: "display:flex;justify-content:flex-end;",
                button { class: "secondary", aria_label: "Language / Idioma", onclick: move |_| language.set(if language() == Lang::Pt { Lang::En } else { Lang::Pt }),
                    if language() == Lang::Pt { "English" } else { "Português" }
                }
            }
            h1 { style: "text-align:center;color:var(--accent);font-size:38px;margin:20px;", "217" }
            section { class: "card", style: "display:grid;gap:14px;",
                a { class: "google-signin", href: "/api/auth/google", aria_label: "{txt.continue_google}",
                    img { src: "/google-signin.png", alt: "{txt.continue_google}", width: "354", height: "80" }
                }
            }
        }
    }
}
