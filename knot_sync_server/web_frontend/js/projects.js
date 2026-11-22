async function loadProjects() {
  try {
    const projects = await apiGet('/api/projects');
    const grid = document.getElementById('projectsGrid');
    if (projects.length === 0) {
      grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;color:#888;padding:48px;">No projects yet</div>';
    } else {
      grid.innerHTML = projects.map(p => `
        <a href="project.html?name=${encodeURIComponent(p.name)}" class="project-card">
          <div class="project-icon">📁</div>
          <div class="project-name">${p.name}</div>
        </a>
      `).join('');
    }
  } catch (err) {
    console.error(err);
    showToast('Failed to load projects', 'error');
  }
}

loadProjects();
