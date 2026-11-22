async function loadDashboard() {
  try {
    const [projects, txns] = await Promise.all([
      apiGet('/api/projects'),
      apiGet('/api/money/transactions')
    ]);

    const spent = txns.filter(t => t.tx_type === 'debit').reduce((sum, t) => sum + t.amount, 0);
    const income = txns.filter(t => t.tx_type === 'credit').reduce((sum, t) => sum + t.amount, 0);
    const pending = txns.filter(t => !t.emoji || t.emoji === '').length;

    document.getElementById('statSpent').textContent = formatCurrency(spent);
    document.getElementById('statIncome').textContent = formatCurrency(income);
    document.getElementById('statProjects').textContent = projects.length;
    document.getElementById('statPending').textContent = pending;

    // Recent transactions (last 5)
    const recent = txns.slice(0, 5);
    const tbody = document.getElementById('recentTxns');
    if (recent.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#888;padding:24px;">No transactions</td></tr>';
    } else {
      tbody.innerHTML = recent.map(t => {
        const typeColor = t.tx_type === 'debit' ? '#ff006e' : '#00ff88';
        const sign = t.tx_type === 'debit' ? '-' : '+';
        const date = formatDate(t.date);
        const cat = t.category || '—';
        return `
          <tr>
            <td>${t.merchant}</td>
            <td><span style="color:${typeColor}">${sign}${t.amount.toFixed(2)}</span></td>
            <td><span class="badge" style="background:${typeColor}22;color:${typeColor}">${t.tx_type}</span></td>
            <td>${date}</td>
            <td>${cat}</td>
          </tr>
        `;
      }).join('');
    }

    // Project cards
    const grid = document.getElementById('projectCards');
    if (projects.length === 0) {
      grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;color:#888;padding:24px;">No projects yet</div>';
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
    showToast('Failed to load dashboard', 'error');
  }
}

loadDashboard();
