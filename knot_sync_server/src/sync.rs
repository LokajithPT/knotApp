use axum::extract::WebSocketUpgrade;
use serde_json::Value;
use crate::db::Database;

pub struct SyncManager {
    db: Database,
}

impl SyncManager {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    pub async fn status(&self) -> Value {
        serde_json::json!({
            "server": "knot_sync_server",
            "version": "0.1.0",
            "status": "online",
            "timestamp": chrono::Utc::now().to_rfc3339(),
        })
    }

    pub async fn pull(&self, since: &str) -> Value {
        let mut changes = Vec::new();
        if let Ok(txns) = self.db.list_transactions().await {
            for t in txns {
                changes.push(serde_json::json!({
                    "type": "transaction",
                    "op": "upsert",
                    "id": t.id,
                    "data": t,
                }));
            }
        }
        serde_json::json!({
            "since": since,
            "changes": changes,
            "count": changes.len(),
        })
    }

    pub async fn push(&self, payload: Value) -> Value {
        let applied = payload.get("changes").and_then(|c| c.as_array()).map(|a| a.len()).unwrap_or(0);
        serde_json::json!({"applied": applied, "status": "ok"})
    }

    pub async fn handle_ws(&self, mut socket: axum::extract::ws::WebSocket) {
        let _ = socket.send(axum::extract::ws::Message::Text(
            serde_json::json!({"type": "connected"}).to_string().into()
        )).await;

        while let Some(Ok(msg)) = socket.recv().await {
            match msg {
                axum::extract::ws::Message::Text(text) => {
                    let echo = text.to_string();
                    let _ = socket.send(axum::extract::ws::Message::Text(
                        serde_json::json!({"type": "ack", "echo": echo}).to_string().into()
                    )).await;
                }
                axum::extract::ws::Message::Close(_) => break,
                _ => {}
            }
        }
    }
}
