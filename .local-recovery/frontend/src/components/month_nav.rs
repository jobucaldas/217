use chrono::NaiveDate;
use dioxus::prelude::*;

#[component]
pub fn MonthNav(
    current: NaiveDate,
    on_prev: EventHandler<()>,
    on_next: EventHandler<()>,
) -> Element {
    rsx! {
        div {
            class: "month-nav",
            style: "display: flex; align-items: center; justify-content: space-between; padding: 16px;",
            button {
                onclick: move |_| on_prev.call(()),
                "←"
            }
            h2 {
                style: "margin: 0 16px;",
                "{current.format(\"%B %Y\")}"
            }
            button {
                onclick: move |_| on_next.call(()),
                "→"
            }
        }
    }
}
