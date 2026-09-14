use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub id: String,
    pub user_id: String,
    pub date: String,
    pub taken: bool,
    pub notes: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpsertRequest {
    pub taken: bool,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonthEntries {
    pub year: i32,
    pub month: i32,
    pub entries: Vec<Entry>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Stats {
    pub year: i32,
    pub month: i32,
    pub total_days: i32,
    pub taken_days: i32,
    pub missed_days: i32,
    pub streak: i32,
}

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq)]
pub struct DayInfo {
    pub date: chrono::NaiveDate,
    pub taken: Option<bool>,
    pub is_today: bool,
    pub is_future: bool,
    pub is_current_month: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub email: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionResponse {
    pub user: Option<User>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReminderPreference {
    pub enabled: bool,
    pub time: String,
    pub timezone: String,
    #[serde(default)]
    pub subscription_count: i32,
    #[serde(default)]
    pub deliverable: bool,
}

impl Default for ReminderPreference {
    fn default() -> Self {
        Self {
            enabled: false,
            time: "20:00".into(),
            timezone: "UTC".into(),
            subscription_count: 0,
            deliverable: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VapidConfig {
    pub configured: bool,
    pub public_key: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PwaStatus {
    pub supported: bool,
    pub secure: bool,
    pub permission: String,
    pub subscribed: bool,
    pub installable: bool,
    pub standalone: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AuthState {
    Loading,
    LoggedOut,
    Authenticated { user: User },
}

impl AuthState {
    pub fn is_authenticated(&self) -> bool {
        matches!(self, AuthState::Authenticated { .. })
    }

    pub fn is_loading(&self) -> bool {
        matches!(self, AuthState::Loading)
    }

    pub fn user(&self) -> Option<&User> {
        match self {
            AuthState::Authenticated { user } => Some(user),
            AuthState::Loading | AuthState::LoggedOut => None,
        }
    }
}
