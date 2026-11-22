use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateProject {
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct NoteMeta {
    pub id: String,
    pub project_id: String,
    pub name: String,
    pub is_voice: bool,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Note {
    pub id: String,
    pub project_id: String,
    pub name: String,
    pub content: String,
    pub is_voice: bool,
    pub voice_path: Option<String>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateNote {
    pub name: String,
    pub content: Option<String>,
    pub is_voice: Option<bool>,
    pub voice_path: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateNote {
    pub name: Option<String>,
    pub content: Option<String>,
    pub is_voice: Option<bool>,
    pub voice_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Transaction {
    pub id: String,
    pub amount: f64,
    pub tx_type: String,
    pub merchant: String,
    pub account_mask: Option<String>,
    pub upi_ref: Option<String>,
    pub upi_id: Option<String>,
    pub balance: Option<f64>,
    pub date: Option<DateTime<Utc>>,
    pub sender: String,
    pub raw_body: Option<String>,
    pub emoji: Option<String>,
    pub category: Option<String>,
    pub is_organized: bool,
    pub reason: Option<String>,
    pub bank: Option<String>,
    pub source: String,
    pub confidence: f64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateTransaction {
    pub amount: f64,
    pub tx_type: String,
    pub merchant: String,
    pub account_mask: Option<String>,
    pub upi_ref: Option<String>,
    pub upi_id: Option<String>,
    pub balance: Option<f64>,
    pub date: Option<DateTime<Utc>>,
    pub sender: String,
    pub raw_body: Option<String>,
    pub emoji: Option<String>,
    pub category: Option<String>,
    pub is_organized: Option<bool>,
    pub reason: Option<String>,
    pub bank: Option<String>,
    pub source: Option<String>,
    pub confidence: Option<f64>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateTransaction {
    pub amount: Option<f64>,
    pub tx_type: Option<String>,
    pub merchant: Option<String>,
    pub account_mask: Option<String>,
    pub upi_ref: Option<String>,
    pub upi_id: Option<String>,
    pub balance: Option<f64>,
    pub date: Option<DateTime<Utc>>,
    pub sender: Option<String>,
    pub raw_body: Option<String>,
    pub emoji: Option<String>,
    pub category: Option<String>,
    pub is_organized: Option<bool>,
    pub reason: Option<String>,
    pub bank: Option<String>,
    pub source: Option<String>,
    pub confidence: Option<f64>,
}

impl Default for UpdateTransaction {
    fn default() -> Self {
        Self {
            amount: None, tx_type: None, merchant: None, account_mask: None,
            upi_ref: None, upi_id: None, balance: None, date: None,
            sender: None, raw_body: None, emoji: None, category: None,
            is_organized: None, reason: None, bank: None, source: None, confidence: None,
        }
    }
}
