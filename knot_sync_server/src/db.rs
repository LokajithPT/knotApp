use sqlx::PgPool;
use chrono::{DateTime, Utc};
use crate::models::*;

#[derive(Clone)]
pub struct Database {
    pub pool: PgPool,
}

impl Database {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /* ---------- Projects ---------- */

    pub async fn list_projects(&self) -> Result<Vec<Project>, sqlx::Error> {
        sqlx::query_as::<_, Project>("SELECT id, name, created_at, updated_at FROM projects ORDER BY name")
            .fetch_all(&self.pool).await
    }

    pub async fn create_project(&self, name: &str) -> Result<Project, sqlx::Error> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now();
        sqlx::query_as::<_, Project>(
            "INSERT INTO projects (id, name, created_at, updated_at) VALUES ($1, $2, $3, $3) RETURNING id, name, created_at, updated_at"
        )
        .bind(&id).bind(name).bind(now).fetch_one(&self.pool).await
    }

    pub async fn get_project(&self, name: &str) -> Result<Option<Project>, sqlx::Error> {
        sqlx::query_as::<_, Project>("SELECT id, name, created_at, updated_at FROM projects WHERE name = $1")
            .bind(name).fetch_optional(&self.pool).await
    }

    pub async fn delete_project(&self, name: &str) -> Result<bool, sqlx::Error> {
        let res = sqlx::query("DELETE FROM projects WHERE name = $1")
            .bind(name).execute(&self.pool).await?;
        Ok(res.rows_affected() > 0)
    }

    /* ---------- Notes ---------- */

    pub async fn list_notes(&self, project: &str) -> Result<Vec<NoteMeta>, sqlx::Error> {
        let proj = self.get_project(project).await?.ok_or(sqlx::Error::RowNotFound)?;
        sqlx::query_as::<_, NoteMeta>(
            "SELECT id, project_id, name, is_voice, voice_path, updated_at FROM notes WHERE project_id = $1 ORDER BY updated_at DESC"
        )
        .bind(&proj.id).fetch_all(&self.pool).await
    }

    pub async fn list_notes_since(&self, since: &DateTime<Utc>) -> Result<Vec<Note>, sqlx::Error> {
        sqlx::query_as::<_, Note>(
            "SELECT id, project_id, name, content, is_voice, voice_path, updated_at FROM notes WHERE updated_at > $1 ORDER BY updated_at DESC"
        )
        .bind(since).fetch_all(&self.pool).await
    }

    pub async fn create_note(&self, project: &str, payload: &super::models::CreateNote) -> Result<Note, sqlx::Error> {
        let proj = self.get_project(project).await?.ok_or(sqlx::Error::RowNotFound)?;
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now();
        let name = payload.name.clone();
        let content = payload.content.clone().unwrap_or_default();
        let is_voice = payload.is_voice.unwrap_or(false);
        sqlx::query_as::<_, Note>(
            "INSERT INTO notes (id, project_id, name, content, is_voice, voice_path, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id, project_id, name, content, is_voice, voice_path, updated_at"
        )
        .bind(&id).bind(&proj.id).bind(name).bind(content).bind(is_voice).bind(&payload.voice_path).bind(now)
        .fetch_one(&self.pool).await
    }

    pub async fn upsert_note(&self, project: &str, payload: &super::models::CreateNote) -> Result<Note, sqlx::Error> {
        let proj = self.get_project(project).await?.ok_or(sqlx::Error::RowNotFound)?;
        let now = chrono::Utc::now();
        let name = payload.name.clone();
        let content = payload.content.clone().unwrap_or_default();
        let is_voice = payload.is_voice.unwrap_or(false);

        // Try update first, then insert if missing
        let existing = sqlx::query_as::<_, Note>(
            "SELECT id, project_id, name, content, is_voice, voice_path, updated_at FROM notes WHERE project_id = $1 AND name = $2"
        )
        .bind(&proj.id).bind(&name)
        .fetch_optional(&self.pool).await?;

        match existing {
            Some(note) => {
                sqlx::query_as::<_, Note>(
                    "UPDATE notes SET content = $1, is_voice = $2, voice_path = $3, updated_at = $4 WHERE id = $5 RETURNING id, project_id, name, content, is_voice, voice_path, updated_at"
                )
                .bind(content).bind(is_voice).bind(&payload.voice_path).bind(now).bind(&note.id)
                .fetch_one(&self.pool).await
            }
            None => {
                let id = uuid::Uuid::new_v4().to_string();
                sqlx::query_as::<_, Note>(
                    "INSERT INTO notes (id, project_id, name, content, is_voice, voice_path, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id, project_id, name, content, is_voice, voice_path, updated_at"
                )
                .bind(&id).bind(&proj.id).bind(name).bind(content).bind(is_voice).bind(&payload.voice_path).bind(now)
                .fetch_one(&self.pool).await
            }
        }
    }

    pub async fn get_note(&self, project: &str, note_name: &str) -> Result<Option<Note>, sqlx::Error> {
        let proj = self.get_project(project).await?.ok_or(sqlx::Error::RowNotFound)?;
        sqlx::query_as::<_, Note>(
            "SELECT id, project_id, name, content, is_voice, voice_path, updated_at FROM notes WHERE project_id = $1 AND name = $2"
        )
        .bind(&proj.id).bind(note_name).fetch_optional(&self.pool).await
    }

    pub async fn update_note(&self, project: &str, note_name: &str, payload: &super::models::UpdateNote) -> Result<Option<Note>, sqlx::Error> {
        let proj = self.get_project(project).await?.ok_or(sqlx::Error::RowNotFound)?;
        let note = self.get_note(project, note_name).await?.ok_or(sqlx::Error::RowNotFound)?;
        let now = chrono::Utc::now();
        let name = payload.name.clone().unwrap_or(note.name);
        let content = payload.content.clone().unwrap_or(note.content);
        let is_voice = payload.is_voice.unwrap_or(note.is_voice);
        let voice_path = payload.voice_path.clone().or(note.voice_path);
        sqlx::query_as::<_, Note>(
            "UPDATE notes SET name = $1, content = $2, is_voice = $3, voice_path = $4, updated_at = $5 WHERE id = $6 RETURNING id, project_id, name, content, is_voice, voice_path, updated_at"
        )
        .bind(name).bind(content).bind(is_voice).bind(voice_path).bind(now).bind(&note.id)
        .fetch_one(&self.pool).await.map(Some)
    }

    pub async fn delete_note(&self, project: &str, note_name: &str) -> Result<bool, sqlx::Error> {
        let proj = self.get_project(project).await?.ok_or(sqlx::Error::RowNotFound)?;
        let res = sqlx::query("DELETE FROM notes WHERE project_id = $1 AND name = $2")
            .bind(&proj.id).bind(note_name).execute(&self.pool).await?;
        Ok(res.rows_affected() > 0)
    }

    /* ---------- Transactions ---------- */

    pub async fn list_transactions(&self) -> Result<Vec<Transaction>, sqlx::Error> {
        sqlx::query_as::<_, Transaction>("SELECT id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at FROM transactions ORDER BY date DESC NULLS LAST, created_at DESC")
            .fetch_all(&self.pool).await
    }

    pub async fn list_transactions_since(&self, since: &DateTime<Utc>) -> Result<Vec<Transaction>, sqlx::Error> {
        sqlx::query_as::<_, Transaction>(
            "SELECT id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at FROM transactions WHERE updated_at > $1 ORDER BY updated_at DESC"
        )
        .bind(since).fetch_all(&self.pool).await
    }

    pub async fn create_transaction(&self, payload: &super::models::CreateTransaction) -> Result<Transaction, sqlx::Error> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now();
        let source = payload.source.clone().unwrap_or("sms".to_string());
        let confidence = payload.confidence.unwrap_or(1.0);
        let is_organized = payload.is_organized.unwrap_or(false);
        sqlx::query_as::<_, Transaction>(
            "INSERT INTO transactions (id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20) RETURNING id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at"
        )
        .bind(&id).bind(payload.amount).bind(&payload.tx_type).bind(&payload.merchant).bind(&payload.account_mask)
        .bind(&payload.upi_ref).bind(&payload.upi_id).bind(payload.balance).bind(payload.date)
        .bind(&payload.sender).bind(&payload.raw_body).bind(&payload.emoji).bind(&payload.category)
        .bind(is_organized).bind(&payload.reason).bind(&payload.bank).bind(source).bind(confidence)
        .bind(now).bind(now).fetch_one(&self.pool).await
    }

    pub async fn upsert_transaction(&self, payload: &super::models::CreateTransaction) -> Result<Transaction, sqlx::Error> {
        let now = chrono::Utc::now();
        let id = payload.id.clone().unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        let source = payload.source.clone().unwrap_or("sms".to_string());
        let confidence = payload.confidence.unwrap_or(1.0);
        let is_organized = payload.is_organized.unwrap_or(false);

        let existing = sqlx::query_as::<_, Transaction>("SELECT id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at FROM transactions WHERE id = $1")
            .bind(&id)
            .fetch_optional(&self.pool).await?;

        match existing {
            Some(t) => {
                sqlx::query_as::<_, Transaction>(
                    "UPDATE transactions SET amount=$1, tx_type=$2, merchant=$3, account_mask=$4, upi_ref=$5, upi_id=$6, balance=$7, date=$8, sender=$9, raw_body=$10, emoji=$11, category=$12, is_organized=$13, reason=$14, bank=$15, source=$16, confidence=$17, updated_at=$18 WHERE id = $19 RETURNING id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at"
                )
                .bind(payload.amount).bind(&payload.tx_type).bind(&payload.merchant).bind(&payload.account_mask)
                .bind(&payload.upi_ref).bind(&payload.upi_id).bind(payload.balance).bind(payload.date)
                .bind(&payload.sender).bind(&payload.raw_body).bind(&payload.emoji).bind(&payload.category)
                .bind(is_organized).bind(&payload.reason).bind(&payload.bank).bind(source).bind(confidence)
                .bind(now).bind(&id)
                .fetch_one(&self.pool).await
            }
            None => {
                sqlx::query_as::<_, Transaction>(
                    "INSERT INTO transactions (id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20) RETURNING id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at"
                )
                .bind(&id).bind(payload.amount).bind(&payload.tx_type).bind(&payload.merchant).bind(&payload.account_mask)
                .bind(&payload.upi_ref).bind(&payload.upi_id).bind(payload.balance).bind(payload.date)
                .bind(&payload.sender).bind(&payload.raw_body).bind(&payload.emoji).bind(&payload.category)
                .bind(is_organized).bind(&payload.reason).bind(&payload.bank).bind(source).bind(confidence)
                .bind(now).bind(now).fetch_one(&self.pool).await
            }
        }
    }

    pub async fn update_transaction(&self, id: &str, payload: &super::models::UpdateTransaction) -> Result<Option<Transaction>, sqlx::Error> {
        let mut t = sqlx::query_as::<_, Transaction>("SELECT id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at FROM transactions WHERE id = $1")
            .bind(id).fetch_optional(&self.pool).await?.ok_or(sqlx::Error::RowNotFound)?;
        let now = chrono::Utc::now();
        if let Some(v) = payload.amount { t.amount = v; }
        if let Some(v) = &payload.tx_type { t.tx_type = v.clone(); }
        if let Some(v) = &payload.merchant { t.merchant = v.clone(); }
        if let Some(v) = &payload.account_mask { t.account_mask = Some(v.clone()); }
        if let Some(v) = &payload.upi_ref { t.upi_ref = Some(v.clone()); }
        if let Some(v) = &payload.upi_id { t.upi_id = Some(v.clone()); }
        if let Some(v) = payload.balance { t.balance = Some(v); }
        if let Some(v) = payload.date { t.date = Some(v); }
        if let Some(v) = &payload.sender { t.sender = v.clone(); }
        if let Some(v) = &payload.raw_body { t.raw_body = Some(v.clone()); }
        if let Some(v) = &payload.emoji { t.emoji = Some(v.clone()); }
        if let Some(v) = &payload.category { t.category = Some(v.clone()); }
        if let Some(v) = payload.is_organized { t.is_organized = v; }
        if let Some(v) = &payload.reason { t.reason = Some(v.clone()); }
        if let Some(v) = &payload.bank { t.bank = Some(v.clone()); }
        if let Some(v) = &payload.source { t.source = v.clone(); }
        if let Some(v) = payload.confidence { t.confidence = v; }
        t.updated_at = now;
        sqlx::query_as::<_, Transaction>(
            "UPDATE transactions SET amount=$1, tx_type=$2, merchant=$3, account_mask=$4, upi_ref=$5, upi_id=$6, balance=$7, date=$8, sender=$9, raw_body=$10, emoji=$11, category=$12, is_organized=$13, reason=$14, bank=$15, source=$16, confidence=$17, updated_at=$18 WHERE id = $19 RETURNING id, amount, tx_type, merchant, account_mask, upi_ref, upi_id, balance, date, sender, raw_body, emoji, category, is_organized, reason, bank, source, confidence, created_at, updated_at"
        )
        .bind(t.amount).bind(&t.tx_type).bind(&t.merchant).bind(&t.account_mask).bind(&t.upi_ref)
        .bind(&t.upi_id).bind(t.balance).bind(t.date).bind(&t.sender).bind(&t.raw_body)
        .bind(&t.emoji).bind(&t.category).bind(t.is_organized).bind(&t.reason).bind(&t.bank)
        .bind(&t.source).bind(t.confidence).bind(now).bind(id)
        .fetch_one(&self.pool).await.map(Some)
    }

    pub async fn delete_transaction(&self, id: &str) -> Result<bool, sqlx::Error> {
        let res = sqlx::query("DELETE FROM transactions WHERE id = $1")
            .bind(id).execute(&self.pool).await?;
        Ok(res.rows_affected() > 0)
    }

    /* ---------- Attachments (audio / images) ---------- */

    pub async fn create_attachment(&self, payload: &CreateAttachment, path: &str) -> Result<Attachment, sqlx::Error> {
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now();
        sqlx::query_as::<_, Attachment>(
            "INSERT INTO attachments (id, project_id, note_id, filename, mime_type, size, path, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id, project_id, note_id, filename, mime_type, size, path, created_at"
        )
        .bind(&id).bind(&payload.project_id).bind(&payload.note_id).bind(&payload.filename).bind(&payload.mime_type).bind(0i64).bind(path).bind(now)
        .fetch_one(&self.pool).await
    }

    pub async fn list_attachments(&self, project_id: Option<&str>) -> Result<Vec<Attachment>, sqlx::Error> {
        match project_id {
            Some(pid) => {
                sqlx::query_as::<_, Attachment>("SELECT id, project_id, note_id, filename, mime_type, size, path, created_at FROM attachments WHERE project_id = $1 ORDER BY created_at DESC")
                    .bind(pid).fetch_all(&self.pool).await
            }
            None => {
                sqlx::query_as::<_, Attachment>("SELECT id, project_id, note_id, filename, mime_type, size, path, created_at FROM attachments ORDER BY created_at DESC")
                    .fetch_all(&self.pool).await
            }
        }
    }

    pub async fn get_attachment_by_filename(&self, filename: &str) -> Result<Option<Attachment>, sqlx::Error> {
        sqlx::query_as::<_, Attachment>("SELECT id, project_id, note_id, filename, mime_type, size, path, created_at FROM attachments WHERE filename = $1")
            .bind(filename).fetch_optional(&self.pool).await
    }

    pub async fn delete_attachment(&self, id: &str) -> Result<bool, sqlx::Error> {
        let res = sqlx::query("DELETE FROM attachments WHERE id = $1")
            .bind(id).execute(&self.pool).await?;
        Ok(res.rows_affected() > 0)
    }
}