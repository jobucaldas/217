#![allow(clippy::uninlined_format_args)]

use crate::models::{
    Entry, MonthEntries, ReminderPreference, SessionResponse, Stats, User, VapidConfig,
};

fn base_url() -> String {
    #[cfg(target_arch = "wasm32")]
    {
        web_sys::window()
            .and_then(|w| w.location().origin().ok())
            .map(|o| format!("{}/api", o.trim_end_matches('/')))
            .unwrap_or_else(|| "/api".to_string())
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        "http://localhost:8080/api".to_string()
    }
}

async fn get(path: &str) -> Result<reqwest::Response, String> {
    let url = format!("{}{}", base_url(), path);
    reqwest::Client::new()
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("request failed: {}", e))
}

async fn post_json(path: &str, body: &impl serde::Serialize) -> Result<reqwest::Response, String> {
    let url = format!("{}{}", base_url(), path);
    reqwest::Client::new()
        .post(&url)
        .json(body)
        .send()
        .await
        .map_err(|e| format!("request failed: {}", e))
}

async fn put_json(path: &str, body: &impl serde::Serialize) -> Result<reqwest::Response, String> {
    let url = format!("{}{}", base_url(), path);
    reqwest::Client::new()
        .put(&url)
        .json(body)
        .send()
        .await
        .map_err(|e| format!("request failed: {}", e))
}

async fn delete_json(
    path: &str,
    body: &impl serde::Serialize,
) -> Result<reqwest::Response, String> {
    let url = format!("{}{}", base_url(), path);
    reqwest::Client::new()
        .delete(&url)
        .json(body)
        .send()
        .await
        .map_err(|e| format!("request failed: {}", e))
}

pub async fn current_session() -> Result<Option<User>, String> {
    let resp = get("/auth/session").await?;
    if !resp.status().is_success() {
        return Err(format!("status: {}", resp.status()));
    }
    let session = resp
        .json::<SessionResponse>()
        .await
        .map_err(|e| format!("parse failed: {}", e))?;
    Ok(session.user)
}

pub async fn logout() -> Result<(), String> {
    let resp = post_json("/auth/logout", &serde_json::json!({})).await?;
    if !resp.status().is_success() {
        return Err(format!("status: {}", resp.status()));
    }
    Ok(())
}

pub async fn list_entries(year: i32, month: i32) -> Result<MonthEntries, String> {
    let resp = get(&format!("/entries?year={}&month={}", year, month)).await?;
    if !resp.status().is_success() {
        return Err(format!("status: {}", resp.status()));
    }
    resp.json::<MonthEntries>()
        .await
        .map_err(|e| format!("parse failed: {}", e))
}

#[allow(dead_code)]
pub async fn get_entry(date: &str) -> Result<Entry, String> {
    let resp = get(&format!("/entries/{}", date)).await?;
    if resp.status().is_success() {
        resp.json::<Entry>()
            .await
            .map_err(|e| format!("parse failed: {}", e))
    } else {
        Err(format!("status: {}", resp.status()))
    }
}

pub async fn upsert_entry(date: &str, taken: bool, notes: &str) -> Result<Entry, String> {
    let body = crate::models::UpsertRequest {
        taken,
        notes: notes.to_string(),
    };
    let resp = post_json(&format!("/entries/{}", date), &body).await?;
    if !resp.status().is_success() {
        return Err(format!("status: {}", resp.status()));
    }
    resp.json::<Entry>()
        .await
        .map_err(|e| format!("parse failed: {}", e))
}

pub async fn get_reminder_preference() -> Result<ReminderPreference, String> {
    let resp = get("/reminders/preferences").await?;
    if !resp.status().is_success() {
        return Err(format!("status: {}", resp.status()));
    }
    resp.json()
        .await
        .map_err(|e| format!("parse failed: {}", e))
}

pub async fn save_reminder_preference(
    preference: &ReminderPreference,
) -> Result<ReminderPreference, String> {
    let resp = put_json("/reminders/preferences", preference).await?;
    if !resp.status().is_success() {
        return Err(resp.text().await.unwrap_or_default());
    }
    resp.json()
        .await
        .map_err(|e| format!("parse failed: {}", e))
}

pub async fn get_vapid_config() -> Result<VapidConfig, String> {
    let resp = get("/reminders/vapid-public-key").await?;
    if !resp.status().is_success() {
        return Err(format!("status: {}", resp.status()));
    }
    resp.json()
        .await
        .map_err(|e| format!("parse failed: {}", e))
}

pub async fn save_push_subscription(subscription_json: &str) -> Result<(), String> {
    let body: serde_json::Value =
        serde_json::from_str(subscription_json).map_err(|e| e.to_string())?;
    let resp = post_json("/reminders/subscriptions", &body).await?;
    if !resp.status().is_success() {
        return Err(resp.text().await.unwrap_or_default());
    }
    Ok(())
}

pub async fn delete_push_subscription(endpoint: &str) -> Result<(), String> {
    let body = serde_json::json!({"endpoint": endpoint});
    let resp = delete_json("/reminders/subscriptions", &body).await?;
    if !resp.status().is_success() {
        return Err(resp.text().await.unwrap_or_default());
    }
    Ok(())
}

#[allow(dead_code)]
pub async fn get_stats(year: i32, month: i32) -> Result<Stats, String> {
    let resp = get(&format!("/stats?year={}&month={}", year, month)).await?;
    if !resp.status().is_success() {
        return Err(format!("status: {}", resp.status()));
    }
    resp.json::<Stats>()
        .await
        .map_err(|e| format!("parse failed: {}", e))
}
