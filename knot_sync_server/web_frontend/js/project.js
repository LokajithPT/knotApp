async function loadProject() {
  const params = new URLSearchParams(window.location.search);
  const name = params.get('name');
  document.getElementById('projectTitle').textContent = name || 'Project';

  try {
    // Get project by name to get its ID
    const projects = await apiGet('/api/projects');
    const project = projects.find(p => p.name === name);
    if (!project) {
      document.getElementById('notesList').innerHTML = '<div style="grid-column:1/-1;text-align:center;color:#888;padding:24px;">Project not found</div>';
      return;
    }

    const notes = await apiGet(`/api/projects/${encodeURIComponent(name)}/notes`);
    const list = document.getElementById('notesList');
    if (notes.length === 0) {
      list.innerHTML = '<div style="grid-column:1/-1;text-align:center;color:#888;padding:24px;">No notes yet</div>';
    } else {
      list.innerHTML = notes.map(n => {
        const preview = n.content.length > 120 ? n.content.substring(0, 120) + '...' : n.content;
        return `
          <div class="note-card${n.is_voice ? ' voice' : ''}">
            <div class="note-icon">${n.is_voice ? '🎙️' : '📄'}</div>
            <div class="note-content">
              <div class="note-title">${n.name}</div>
              <div class="note-preview">${preview}</div>
              <div class="note-meta">Updated: ${formatDate(n.updated_at)}</div>
            </div>
          </div>
        `;
      }).join('');
    }
  } catch (err) {
    console.error(err);
    showToast('Failed to load project notes', 'error');
  }
}

loadProject();
