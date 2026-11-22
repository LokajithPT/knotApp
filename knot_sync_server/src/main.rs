use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use axum::{
    extract::{Path, Query, State, WebSocketUpgrade},
    http::{header, StatusCode},
    response::{IntoResponse, Json, Response},
    routing::{get, post, put, delete},
    Router,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use tokio::fs;
use tracing::info;

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

    let pool = PgPool::connect(&database_url).await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    info!("Database migrated");

    let db = Database::new(pool);
    let sync = Arc::new(SyncManager::new(db.clone()));
    let state = AppState { db, sync };

    let app = Router::new()
        // API routes
        .route("/api/health", get(health))
        .route("/api/projects", get(list_projects).post(create_project))
        .route("/api/projects/{name}", get(get_project).delete(delete_project))
        .route("/api/projects/{project}/notes", get(list_notes).post(create_note))
        .route("/api/projects/{project}/notes/{note}", get(get_note).put(update_note).delete(delete_note))
        .route("/api/money/transactions", get(list_transactions).post(create_transaction))
        .route("/api/money/transactions/{id}", put(update_transaction).delete(delete_transaction))
        .route("/api/sync/status", get(sync_status))
        .route("/api/sync/pull", get(sync_pull))
        .route("/api/sync/push", post(sync_push))
        .route("/api/sync/stream", get(ws_stream))
        // Static routes - specific pages
        .route("/", get(serve_index))
        .route("/index.html", get(serve_index))
        .route("/projects.html", get(serve_projects))
        .route("/money.html", get(serve_money))
        .route("/project.html", get(serve_project))
        // Static assets
        .route("/css/{*path}", get(serve_css))
        .route("/js/{*path}", get(serve_js))
        .layer(tower_http::cors::CorsLayer::permissive())
        .with_state(state.clone());

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    info!("Server listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn serve_file(path: &str) -> Response {
    let file_path = PathBuf::from(format!("web_frontend/{}", path));
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

async fn serve_index() -> Response {
    serve_file("index.html").await
}

async fn serve_projects() -> Response {
    serve_file("projects.html").await
}

async fn serve_money() -> Response {
    serve_file("money.html").await
}

async fn serve_project() -> Response {
    serve_file("project.html").await
}

async fn serve_css(Path(path): Path<String>) -> Response {
    serve_file(&format!("css/{}", path)).await
}

async fn serve_js(Path(path): Path<String>) -> Response {
    serve_file(&format!("js/{}", path)).await
}

async fn health(State(_state): State<AppState>) -> Json<serde_json::Value> {
    Json(serde_json::json!({"status": "ok"}))
}

async fn list_projects(State(state): State<AppState>) -> Result<Json<Vec<Project>>, StatusCode> {
    state.db.list_projects().await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn create_project(State(state): State<AppState>, Json(payload): Json<CreateProject>) -> Result<Json<Project>, StatusCode> {
    state.db.create_project(&payload.name).await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn get_project(State(state): State<AppState>, Path(name): Path<String>) -> Result<Json<Project>, StatusCode> {
    state.db.get_project(&name).await.map(|p| p.map(Json).ok_or(StatusCode::NOT_FOUND)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn delete_project(State(state): State<AppState>, Path(name): Path<String>) -> StatusCode {
    state.db.delete_project(&name).await.unwrap_or(false);
    StatusCode::NO_CONTENT
}

async fn list_notes(State(state): State<AppState>, Path(project): Path<String>) -> Result<Json<Vec<NoteMeta>>, StatusCode> {
    state.db.list_notes(&project).await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn create_note(State(state): State<AppState>, Path(project): Path<String>, Json(payload): Json<CreateNote>) -> Result<Json<Note>, StatusCode> {
    state.db.create_note(&project, &payload).await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn get_note(State(state): State<AppState>, Path((project, note)): Path<(String, String)>) -> Result<Json<Note>, StatusCode> {
    state.db.get_note(&project, &note).await.map(|n| n.map(Json).ok_or(StatusCode::NOT_FOUND)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn update_note(State(state): State<AppState>, Path((project, note)): Path<(String, String)>, Json(payload): Json<UpdateNote>) -> Result<Json<Note>, StatusCode> {
    state.db.update_note(&project, &note, &payload).await.map(|n| n.map(Json).ok_or(StatusCode::NOT_FOUND)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn delete_note(State(state): State<AppState>, Path((project, note)): Path<(String, String)>) -> StatusCode {
    state.db.delete_note(&project, &note).await.unwrap_or(false);
    StatusCode::NO_CONTENT
}

async fn list_transactions(State(state): State<AppState>) -> Result<Json<Vec<Transaction>>, StatusCode> {
    state.db.list_transactions().await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn create_transaction(State(state): State<AppState>, Json(payload): Json<CreateTransaction>) -> Result<Json<Transaction>, StatusCode> {
    state.db.create_transaction(&payload).await.map(Json).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn update_transaction(State(state): State<AppState>, Path(id): Path<String>, Json(payload): Json<UpdateTransaction>) -> Result<Json<Transaction>, StatusCode> {
    state.db.update_transaction(&id, &payload).await.map(|t| t.map(Json).ok_or(StatusCode::NOT_FOUND)).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
}

async fn delete_transaction(State(state): State<AppState>, Path(id): Path<String>) -> StatusCode {
    state.db.delete_transaction(&id).await.unwrap_or(false);
    StatusCode::NO_CONTENT
}

async fn sync_status(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(state.sync.status().await)
}

async fn sync_pull(Query(params): Query<HashMap<String, String>>, State(state): State<AppState>) -> Json<serde_json::Value> {
    let since = params.get("since").cloned().unwrap_or_default();
    Json(state.sync.pull(&since).await)
}

async fn sync_push(State(state): State<AppState>, Json(payload): Json<serde_json::Value>) -> Json<serde_json::Value> {
    Json(state.sync.push(payload).await)
}

async fn ws_stream(ws: WebSocketUpgrade, State(state): State<AppState>) -> Response {
    let sync_clone = state.sync.clone();
    ws.on_upgrade(move |socket| {
        let sync = sync_clone.clone();
        async move {
            sync.handle_ws(socket).await
        }
    }).into_response()
}
