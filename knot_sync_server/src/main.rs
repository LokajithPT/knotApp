use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use axum::{
    extract::{Path as AxumPath, Query, State, WebSocketUpgrade},
    http::{header, HeaderMap, Request, StatusCode},
    middleware::{self, Next},
    response::{IntoResponse, Json, Response},
    routing::{get, post, put, delete},
    Router,
};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;
use tokio::fs;
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing::{info, Level};

pub mod db;
pub mod models;
pub mod sync;

use crate::models::*;
use crate::db::Database;
use crate::sync::SyncManager;

#[derive(Clone)]
pub struct AppState {
    pub db: Database,
    pub sync: Arc<SyncManager>,
    pub api_key: String,
    pub upload_dir: PathBuf,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://knot:knot@localhost:5432/knot".to_string());
    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse()
        .unwrap_or(8080);
    let api_key = std::env::var("API_KEY")
        .unwrap_or_else(|_| "knot-sync-key-2024".to_string());
    let upload_dir = PathBuf::from(std::env::var("UPLOAD_DIR").unwrap_or_else(|_| "./uploads".to_string()));

    // Ensure upload directory exists
    fs::create_dir_all(&upload_dir).await?;

    let pool = PgPool::connect(&database_url).await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    info!("Database migrated");

    // Run attachment migration if table doesn't exist yet
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS attachments (
            id VARCHAR PRIMARY KEY,
            project_id VARCHAR,
            note_id VARCHAR,
            filename VARCHAR NOT NULL,
            mime_type VARCHAR,
            size BIGINT DEFAULT 0,
            path VARCHAR NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )"
    ).execute(&pool).await?;
    info!("Attachments table ensured");

    let db = Database::new(pool);
    let sync = Arc::new(SyncManager::new(db.clone()));
    let state = AppState {
        db,
        sync,
        api_key,
        upload_dir,
    };
    let api_key_copy = state.api_key.clone();

    // --- API routes (require API key) ---
    let api = Router::new()
        .route("/health", get(health))
        .route("/projects", get(list_projects).post(create_project))
        .route("/projects/{name}", get(get_project).delete(delete_project))
        .route("/projects/{project}/notes", get(list_notes).post(create_note))
        .route("/projects/{project}/notes/{note}", get(get_note).put(update_note).delete(delete_note))
        .route("/money/transactions", get(list_transactions).post(create_transaction))
        .route("/money/transactions/{id}", put(update_transaction).delete(delete_transaction))
        .route("/sync/status", get(sync_status))
        .route("/sync/pull", get(sync_pull))
        .route("/sync/push", post(sync_push))
        .route("/sync/stream", get(ws_stream))
        .route("/files/upload", post(upload_file))
        .route("/files/{*filename}", get(download_file))
        .route_layer(middleware::from_fn_with_state(state.clone(), auth_middleware))
        .with_state(state.clone());

    // --- Static web frontend (no auth) ---
    let app = Router::new()
        .merge(api)
        .route("/", get(serve_dashboard))
        .route("/dashboard.html", get(serve_dashboard))
        .route("/assets/{*path}", get(serve_asset))
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(|_req: &Request<axum::body::Body>| {
                    tracing::info_span!("http_request", method = %_req.method(), uri = %_req.uri())
                })
                .on_request(|_req: &Request<axum::body::Body>, _span: &tracing::Span| {
                    tracing::debug!("request started")
                })
                .on_response(|_res: &Response, _latency: std::time::Duration, _span: &tracing::Span| {
                    tracing::debug!("request completed")
                }),
        )
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server listening on {}", addr);
    info!("API key: {}", api_key_copy);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

/* ---------- Auth middleware (constant shared key) ---------- */

async fn auth_middleware(
    State(state): State<AppState>,
    headers: HeaderMap,
    request: Request<axum::body::Body>,
    next: Next,
) -> Result<Response, StatusCode> {
    let key = headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .or_else(|| headers.get("X-API-Key").and_then(|v| v.to_str().ok()));

    match key {
        Some(k) if k == state.api_key => Ok(next.run(request).await),
        _ => Err(StatusCode::UNAUTHORIZED),
    }
}

/* ---------- Static file serving (web frontend) ---------- */

async fn serve_file(_state: &AppState, relative_path: &str) -> Response {
    let file_path = PathBuf::from(format!("web_frontend/{}", relative_path));
    match fs::read(&file_path).await {
        Ok(content) => {
            let mime = mime_guess::from_path(&file_path).first_or_octet_stream();
            Response::builder()
                .header(header::CONTENT_TYPE, mime.as_ref())
                .body(axum::body::Body::from(content))
                .unwrap()
        }
        Err(_) => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn serve_dashboard(State(_state): State<AppState>) -> Response {
    serve_file(&_state, "dashboard.html").await
}

async fn serve_asset(State(_state): State<AppState>, AxumPath(path): AxumPath<String>) -> Response {
    serve_file(&_state, &format!("assets/{}", path)).await
}

/* ---------- API handlers ---------- */

async fn health(State(_state): State<AppState>) -> Json<Value> {
    Json(serde_json::json!({"status": "ok"}))
}

async fn list_projects(State(state): State<AppState>) -> Result<Json<Vec<Project>>, StatusCode> {
    state.db.list_projects().await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn create_project(State(state): State<AppState>, Json(payload): Json<CreateProject>) -> Result<Json<Project>, StatusCode> {
    state.db.create_project(&payload.name).await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn get_project(State(state): State<AppState>, AxumPath(name): AxumPath<String>) -> Result<Json<Project>, StatusCode> {
    state.db.get_project(&name).await.map(|p| p.map(Json).ok_or(StatusCode::NOT_FOUND)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn delete_project(State(state): State<AppState>, AxumPath(name): AxumPath<String>) -> StatusCode {
    state.db.delete_project(&name).await.unwrap_or(false);
    StatusCode::NO_CONTENT
}

async fn list_notes(State(state): State<AppState>, AxumPath(project): AxumPath<String>) -> Result<Json<Vec<NoteMeta>>, StatusCode> {
    state.db.list_notes(&project).await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn create_note(State(state): State<AppState>, AxumPath(project): AxumPath<String>, Json(payload): Json<CreateNote>) -> Result<Json<Note>, StatusCode> {
    state.db.create_note(&project, &payload).await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn get_note(State(state): State<AppState>, AxumPath((project, note)): AxumPath<(String, String)>) -> Result<Json<Note>, StatusCode> {
    state.db.get_note(&project, &note).await.map(|n| n.map(Json).ok_or(StatusCode::NOT_FOUND)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn update_note(State(state): State<AppState>, AxumPath((project, note)): AxumPath<(String, String)>, Json(payload): Json<UpdateNote>) -> Result<Json<Note>, StatusCode> {
    state.db.update_note(&project, &note, &payload).await.map(|n| n.map(Json).ok_or(StatusCode::NOT_FOUND)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn delete_note(State(state): State<AppState>, AxumPath((project, note)): AxumPath<(String, String)>) -> StatusCode {
    state.db.delete_note(&project, &note).await.unwrap_or(false);
    StatusCode::NO_CONTENT
}

async fn list_transactions(State(state): State<AppState>) -> Result<Json<Vec<Transaction>>, StatusCode> {
    state.db.list_transactions().await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn create_transaction(State(state): State<AppState>, Json(payload): Json<CreateTransaction>) -> Result<Json<Transaction>, StatusCode> {
    state.db.create_transaction(&payload).await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn update_transaction(State(state): State<AppState>, AxumPath(id): AxumPath<String>, Json(payload): Json<UpdateTransaction>) -> Result<Json<Transaction>, StatusCode> {
    state.db.update_transaction(&id, &payload).await.map(|t| t.map(Json).ok_or(StatusCode::NOT_FOUND)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn delete_transaction(State(state): State<AppState>, AxumPath(id): AxumPath<String>) -> StatusCode {
    state.db.delete_transaction(&id).await.unwrap_or(false);
    StatusCode::NO_CONTENT
}

async fn sync_status(State(state): State<AppState>) -> Json<Value> {
    Json(state.sync.status().await)
}

async fn sync_pull(Query(params): Query<HashMap<String, String>>, State(state): State<AppState>) -> Json<Value> {
    let since = params.get("since").cloned().unwrap_or_default();
    Json(state.sync.pull(&since).await)
}

async fn sync_push(State(state): State<AppState>, Json(payload): Json<Value>) -> Json<Value> {
    Json(state.sync.push(payload).await)
}

async fn ws_stream(ws: WebSocketUpgrade, State(state): State<AppState>) -> Response {
    let sync = state.sync.clone();
    ws.on_upgrade(move |socket| {
        let sync = sync.clone();
        async move {
            sync.handle_ws(socket).await
        }
    }).into_response()
}

/* ---------- File upload / download (audio, images, etc.) ---------- */

async fn upload_file(
    State(state): State<AppState>,
    Json(payload): Json<UploadFileRequest>,
) -> Result<Json<Value>, StatusCode> {
    // Decode base64 file data
    use base64::Engine as _;
    let data = match base64::engine::general_purpose::STANDARD.decode(payload.data.as_bytes()) {
        Ok(d) => d,
        Err(_) => return Err(StatusCode::BAD_REQUEST),
    };

    // Safe filename: prefix with uuid to avoid collisions
    let id = uuid::Uuid::new_v4().to_string();
    let safe_name = format!("{}_{}", id, payload.filename);
    let disk_path = state.upload_dir.join(&safe_name);

    fs::write(&disk_path, &data).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Record attachment
    let att_payload = CreateAttachment {
        project_id: None,
        note_id: None,
        filename: safe_name.clone(),
        mime_type: payload.mime_type.clone(),
    };
    let att = state.db.create_attachment(&att_payload, &safe_name).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(serde_json::json!({
        "status": "ok",
        "files": [{
            "id": att.id,
            "filename": att.filename,
            "mime_type": att.mime_type,
            "size": data.len(),
            "url": format!("/files/{}", att.filename),
        }],
    })))
}

async fn download_file(
    State(state): State<AppState>,
    AxumPath(filename): AxumPath<String>,
) -> Response {
    // Look up attachment to get mime type and path
    let att = match state.db.get_attachment_by_filename(&filename).await {
        Ok(Some(a)) => a,
        _ => return StatusCode::NOT_FOUND.into_response(),
    };

    let file_path = state.upload_dir.join(&att.path);
    match fs::read(&file_path).await {
        Ok(content) => {
            let mime = mime_guess::from_path(&file_path).first_or_octet_stream();
            Response::builder()
                .header(header::CONTENT_TYPE, mime.as_ref())
                .header(header::CONTENT_DISPOSITION, format!("inline; filename=\"{}\"", att.filename))
                .body(axum::body::Body::from(content))
                .unwrap()
        }
        Err(_) => StatusCode::NOT_FOUND.into_response(),
    }
}