async function loadMoney() {
  try {
    const txns = await apiGet('/api/money/transactions');

    const spent = txns.filter(t => t.tx_type === 'debit').reduce((sum, t) => sum + t.amount, 0);
    const income = txns.filter(t => t.tx_type === 'credit').reduce((sum, t) => sum + t.amount, 0);

    document.getElementById('statSpent').textContent = formatCurrency(spent);
    document.getElementById('statIncome').textContent = formatCurrency(income);
    document.getElementById('statCount').textContent = txns.length;

    // Group by emoji
    const groups = {};
    txns.forEach(t => {
      const key = t.emoji || '❓';
      if (!groups[key]) groups[key] = [];
      groups[key].push(t);
    });

    const container = document.getElementById('emojiGroups');
    const keys = Object.keys(groups).sort();
    if (keys.length === 0) {
      container.innerHTML = '<div style="text-align:center;color:#888;padding:24px;">No transactions</div>';
    } else {
      container.innerHTML = keys.map(key => {
        const items = groups[key];
        const total = items.reduce((sum, t) => sum + t.amount, 0);
        return `
          <div class="emoji-group">
            <div class="emoji-header">
              <span class="emoji-badge">${key}</span>
              <div class="emoji-info">
                <div class="emoji-total">${formatCurrency(total)}</div>
                <div class="emoji-count">${items.length} transaction${items.length !== 1 ? 's' : ''}</div>
              </div>
            </div>
            <div class="emoji-items">
              ${items.map(t => {
                const typeColor = t.tx_type === 'debit' ? '#ff006e' : '#00ff88';
                const sign = t.tx_type === 'debit' ? '-' : '+';
                return `
                  <div class="txn-item">
                    <div class="txn-main">
                      <div class="txn-merchant">${t.merchant}</div>
                      <div class="txn-amount" style="color:${typeColor}">${sign}${t.amount.toFixed(2)}</div>
                    </div>
                    <div class="txn-meta">
                      <span class="txn-type">${t.tx_type}</span>
                      <span class="txn-date">${formatDate(t.date)}</span>
                      ${t.bank ? `<span class="txn-bank">${t.bank}</span>` : ''}
                    </div>
                    ${t.reason ? `<div class="txn-reason">📝 ${t.reason}</div>` : ''}
                  </div>
                `;
              }).join('')}
            </div>
          </div>
        `;
      }).join('');
    }
  } catch (err) {
    console.error(err);
    showToast('Failed to load transactions', 'error');
  }
}

loadMoney();
