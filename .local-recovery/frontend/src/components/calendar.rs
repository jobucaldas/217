use chrono::{Datelike, NaiveDate};
use dioxus::prelude::*;
use std::collections::HashMap;

use crate::i18n::{month_name, t, Lang};
use crate::models::Entry;

fn days_in_month(year: i32, month: u32) -> u32 {
    if month == 12 {
        NaiveDate::from_ymd_opt(year + 1, 1, 1)
    } else {
        NaiveDate::from_ymd_opt(year, month + 1, 1)
    }
    .and_then(|date| date.pred_opt())
    .map(|date| date.day())
    .unwrap_or(31)
}

fn day_status_presentation(status: Option<bool>, is_future: bool) -> (&'static str, &'static str) {
    if is_future {
        return ("day-future", "");
    }
    match status {
        Some(true) => ("day-taken", "✓"),
        Some(false) => ("day-missed", "✕"),
        None => ("day-unrecorded", ""),
    }
}

fn build_month_grid(year: i32, month: u32) -> Vec<Option<u32>> {
    let first_day = NaiveDate::from_ymd_opt(year, month, 1).unwrap();
    let mut cells = vec![None; first_day.weekday().num_days_from_sunday() as usize];
    cells.extend((1..=days_in_month(year, month)).map(Some));
    while cells.len() % 7 != 0 {
        cells.push(None);
    }
    cells
}

#[component]
pub fn Calendar(
    months: Vec<(i32, u32)>,
    entries: HashMap<String, Entry>,
    today: NaiveDate,
    on_toggle: EventHandler<(String, Option<bool>, String)>,
    on_scroll_more: EventHandler<(bool,)>,
) -> Element {
    let language = use_context::<Signal<Lang>>();
    let lang = language();
    let txt = t(&lang);
    let weekday_labels = if lang == Lang::Pt {
        ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
    } else {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    };

    rsx! {
        section { class: "status-legend", aria_label: "{txt.legend}",
            span { class: "legend-item", span { class: "legend-swatch legend-taken", aria_hidden: "true", "✓" }, "{txt.legend_taken}" }
            span { class: "legend-item", span { class: "legend-swatch legend-missed", aria_hidden: "true", "✕" }, "{txt.legend_missed}" }
            span { class: "legend-item", span { class: "legend-swatch legend-unrecorded", aria_hidden: "true" }, "{txt.legend_unrecorded}" }
        }
        div { class: "scroll-container", id: "calendar-scroll",
            onscroll: move |event| {
                let top = event.scroll_top() as i32;
                let height = event.scroll_height();
                let client = event.client_height();
                if top < 120 { on_scroll_more.call((true,)); }
                if top + client > height - 180 { on_scroll_more.call((false,)); }
            },
            for (year, month) in months {
                section { id: "month-{year:04}-{month:02}", style: "margin:0 auto 10px;max-width:430px;",
                    h2 { style: "text-align:center;font-size:18px;margin:0;padding:12px 0 8px;position:sticky;top:0;background:var(--bg);z-index:2;", "{month_name(lang, month)} {year}" }
                    div { class: "month-grid", style: "font-weight:700;color:var(--muted);text-align:center;font-size:12px;padding-bottom:4px;",
                        for label in weekday_labels { div { "{label}" } }
                    }
                    div { class: "month-grid",
                        for cell in build_month_grid(year, month) {
                            if let Some(day) = cell {
                                {
                                    let date = NaiveDate::from_ymd_opt(year, month, day).unwrap();
                                    let date_str = date.format("%Y-%m-%d").to_string();
                                    let entry = entries.get(&date_str);
                                    let status = entry.map(|value| value.taken);
                                    let notes = entry.map(|value| value.notes.clone()).unwrap_or_default();
                                    let is_today = date == today;
                                    let is_future = date > today;
                                    let (status_class, indicator) = day_status_presentation(status, is_future);
                                    let status_label = if is_future {
                                        txt.unrecorded
                                    } else {
                                        match status {
                                            Some(true) => txt.taken,
                                            Some(false) => txt.not_taken,
                                            None => txt.unrecorded,
                                        }
                                    };
                                    let today_class = if is_today { " day-today" } else { "" };
                                    let aria = format!("{}: {}{}", date_str, status_label, if is_today { txt.today_aria } else { "" });
                                    let ds = date_str.clone();
                                    let ns = notes.clone();
                                    rsx! {
                                        button { key: "{date_str}", class: "day {status_class}{today_class}", disabled: is_future, aria_label: "{aria}",
                                            onclick: move |_| on_toggle.call((ds.clone(), status, ns.clone())),
                                            span { style: "font-weight:800;", "{day}" }
                                            if is_today { small { style: "font-size:9px;font-weight:800;", "{txt.today}" } }
                                            if !indicator.is_empty() { span { class: "day-indicator", aria_hidden: "true", "{indicator}" } }
                                            if !notes.is_empty() { span { class: "day-notes", aria_label: "{txt.notes_label}", "●" } }
                                        }
                                    }
                                }
                            } else { div { style: "min-height:44px;" } }
                        }
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn month_grid_handles_leap_year_and_alignment() {
        assert_eq!(days_in_month(2024, 2), 29);
        assert_eq!(days_in_month(2025, 2), 28);
        assert_eq!(
            build_month_grid(2026, 5)
                .iter()
                .take_while(|day| day.is_none())
                .count(),
            5
        );
        assert_eq!(build_month_grid(2026, 5).len() % 7, 0);
    }

    #[test]
    fn status_presentation_distinguishes_taken_missed_and_future() {
        assert_eq!(
            day_status_presentation(Some(true), false),
            ("day-taken", "✓")
        );
        assert_eq!(
            day_status_presentation(Some(false), false),
            ("day-missed", "✕")
        );
        assert_eq!(day_status_presentation(None, true), ("day-future", ""));
        assert_eq!(
            day_status_presentation(Some(true), true),
            ("day-future", "")
        );
        assert_eq!(
            day_status_presentation(Some(false), true),
            ("day-future", "")
        );
        assert_eq!(day_status_presentation(None, false), ("day-unrecorded", ""));
    }

    #[test]
    fn month_names_follow_language() {
        assert_eq!(month_name(Lang::Pt, 3), "Março");
        assert_eq!(month_name(Lang::En, 3), "March");
    }
}
