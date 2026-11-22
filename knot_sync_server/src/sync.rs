use axum::extract::ws::{Message, WebSocket};
use serde_json::Value;
use tokio::sync::broadcast;
use crate::db::Database;
use crate::models::{SyncChange, CreateTransaction, CreateNote};
use axum::extract::ws::Utf8Bytes;

pub struct SyncManager {
    db: Database,
    /// Broadcast channel for real-time change events pushed to WebSocket clients.
    tx: broadcast::Sender<Value>,
}

impl SyncManager {
    pub fn new(db: Database) -> Self {
        let (tx, _rx) = broadcast::channel(128);
        Self { db, tx }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Value> {
        self.tx.subscribe()
    }

    pub async fn status(&self) -> Value {
        serde_json::json!({
            "server": "knot_sync_server",
            "version": "0.1.0",
            "status": "online",
            "timestamp": chrono::Utc::now().to_rfc3339(),
        })
    }

    /* ---------- Pull (server -> client) ---------- */

    pub async fn pull(&self, since: &str) -> Value {
        let since_dt = chrono::DateTime::parse_from_rfc3339(since)
            .ok()
            .map(|dt| dt.with_timezone(&chrono::Utc));

        let mut changes = Vec::new();

        // Transactions changed since cursor
        if let Some(s) = since_dt {
            if let Ok(txns) = self.db.list_transactions_since(&s).await {
                for t in txns {
                    changes.push(serde_json::json!({
                        "type": "transaction",
                        "op": "upsert",
                        "id": t.id,
                        "data": t,
                        "updated_at": t.updated_at.to_rfc3339(),
                    }));
                }
            }
        } else {
            // No cursor: return everything (initial sync)
            if let Ok(txns) = self.db.list_transactions().await {
                for t in txns {
                    changes.push(serde_json::json!({
                        "type": "transaction",
                        "op": "upsert",
                        "id": t.id,
                        "data": t,
                        "updated_at": t.updated_at.to_rfc3339(),
                    }));
                }
            }
        }

        // Notes changed since cursor
        if let Some(s) = since_dt {
            if let Ok(notes) = self.db.list_notes_since(&s).await {
                for n in notes {
                    changes.push(serde_json::json!({
                        "type": "note",
                        "op": "upsert",
                        "id": n.id,
                        "data": n,
                        "updated_at": n.updated_at.to_rfc3339(),
                    }));
                }
            }
        } else {
            // No cursor: we don't have a global "list all notes" without project,
            // so return empty for notes on initial pull unless client asks per-project.
        }

        serde_json::json!({
            "since": since,
            "changes": changes,
            "count": changes.len(),
        })
    }

    /* ---------- Push (client -> server) ---------- */

    pub async fn push(&self, payload: Value) -> Value {
        let changes: Vec<SyncChange> = match serde_json::from_value(payload.get("changes").cloned().unwrap_or(Value::Null)) {
            Ok(c) => c,
            Err(_) => return serde_json::json!({"applied": 0, "status": "error", "error": "invalid changes payload"}),
        };

        let mut applied = 0i64;
        let mut last_events: Vec<Value> = Vec::new();

        for change in changes {
            match change.r#type.as_str() {
                "transaction" => {
                    let data = change.data;
                    let tx: Result<CreateTransaction, _> = serde_json::from_value(data);
                    match tx {
                        Ok(payload) => {
                            if let Ok(_t) = self.db.upsert_transaction(&payload).await {
                                applied += 1;
                                last_events.push(serde_json::json!({
                                    "type": "transaction",
                                    "op": "upsert",
                                    "id": payload.id.unwrap_or_default(),
                                }));
                            }
                        }
                        Err(e) => tracing::warn!("failed to parse transaction change: {}", e),
                    }
                }
                "note" => {
                    let data = change.data;
                    // We need project + note payload. Expect data to contain project + CreateNote fields.
                    let project_name = data.get("project").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    let note: Result<CreateNote, _> = serde_json::from_value(data.clone());
                    match note {
                        Ok(payload) => {
                            if project_name.is_empty() {
                                tracing::warn!("note change missing project");
                                continue;
                            }
                            if let Ok(_n) = self.db.upsert_note(&project_name, &payload).await {
                                applied += 1;
                                last_events.push(serde_json::json!({
                                    "type": "note",
                                    "op": "upsert",
                                    "project": project_name,
                                    "name": payload.name,
                                }));
                            }
                        }
                        Err(e) => tracing::warn!("failed to parse note change: {}", e),
                    }
                }
                "delete" => {
                    // Generic delete by id - we don't know the table, skip safely
                    tracing::warn!("delete op not implemented for type {}", change.r#type);
                }
                _ => {
                    tracing::warn!("unknown change type: {}", change.r#type);
                }
            }
        }

        // Broadcast change events to WebSocket subscribers
        if !last_events.is_empty() {
            let _ = self.tx.send(serde_json::json!({
                "type": "sync",
                "applied": applied,
                "changes": last_events,
                "timestamp": chrono::Utc::now().to_rfc3339(),
            }));
        }

        serde_json::json!({"applied": applied, "status": "ok"})
    }

    /* ---------- WebSocket stream ---------- */

    pub async fn handle_ws(&self, mut socket: WebSocket) {
        let mut rx = self.subscribe();

        // Send hello immediately
        let _ = socket.send(Message::Text(
            Utf8Bytes::from(serde_json::json!({"type": "connected", "status": "ok"}).to_string())
        )).await;

        loop {
            tokio::select! {
                // Incoming messages from client (we echo ack but mainly use it to detect disconnect)
                Some(msg_result) = socket.recv() => {
                    match msg_result {
                        Ok(Message::Text(text)) => {
                            let _ = socket.send(Message::Text(
                                Utf8Bytes::from(serde_json::json!({"type": "ack", "echo": text.to_string()}).to_string())
                            )).await;
                        }
                        Ok(Message::Close(_)) => break,
                        Ok(_) => {}
                        Err(_) => break,
                    }
                }
                // Broadcast events from the server
                Ok(event) = rx.recv() => {
                    if socket.send(Message::Text(Utf8Bytes::from(event.to_string()))).await.is_err() {
                        break;
                    }
                }
                else => break,
            }
        }
    }
}