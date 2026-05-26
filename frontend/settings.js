/* Flowey settings UI — plain vanilla JS, no build step. */

const { invoke } = window.__TAURI__.core;

// ── DOM refs ────────────────────────────────────────────────
const $  = id => document.getElementById(id);
const modelPath    = $('model-path');
const modelBrowse  = $('model-browse');
const modelStatus  = $('model-status');
const hotkeyInput  = $('hotkey');
const langSelect   = $('language');
const autostartCb  = $('autostart');
const dictEntries  = $('dict-entries');
const dictAdd      = $('dict-add');
const dictTestIn   = $('dict-test-input');
const dictTestOut  = $('dict-test-output');
const saveBtn      = $('save');
const saveStatus   = $('save-status');
const modelLink    = $('model-link');

// ── Suppress navigation on the model-download link ──────────
modelLink.addEventListener('click', e => e.preventDefault());

// ── Load config on open ─────────────────────────────────────
async function loadConfig() {
  try {
    const cfg = await invoke('get_config');
    modelPath.value   = cfg.modelPath   ?? '';
    hotkeyInput.value = cfg.hotkey      ?? '';
    langSelect.value  = cfg.language    ?? 'auto';
    autostartCb.checked = cfg.autostart ?? false;

    // Dictionary
    dictEntries.innerHTML = '';
    for (const [key, val] of Object.entries(cfg.dictionary ?? {})) {
      addDictRow(key, val);
    }
  } catch (e) {
    console.error('Failed to load config:', e);
  }
}

loadConfig();

// ── Browse for model file (Rust-side native dialog) ─────────
modelBrowse.addEventListener('click', async () => {
  try {
    const selected = await invoke('browse_model_file');
    if (selected) {
      modelPath.value = selected;
      setModelStatus('', '');
    }
  } catch (e) {
    console.error('File dialog error:', e);
  }
});

// ── Dictionary ───────────────────────────────────────────────
function addDictRow(key = '', value = '') {
  const row = document.createElement('div');
  row.className = 'dict-row';
  row.innerHTML = `
    <input type="text" class="dict-key"   value="${esc(key)}"   placeholder="word" spellcheck="false" />
    <span class="dict-arrow">→</span>
    <input type="text" class="dict-val"   value="${esc(value)}" placeholder="replacement" spellcheck="false" />
    <button class="dict-del secondary" title="Remove">✕</button>
  `;
  row.querySelector('.dict-del').addEventListener('click', () => row.remove());

  // Live dict test on any change
  row.addEventListener('input', debouncedDictTest);

  dictEntries.appendChild(row);
  row.querySelector('.dict-key').focus();
}

dictAdd.addEventListener('click', () => addDictRow());

function collectDict() {
  const dict = {};
  for (const row of dictEntries.querySelectorAll('.dict-row')) {
    const k = row.querySelector('.dict-key').value.trim().toLowerCase();
    const v = row.querySelector('.dict-val').value.trim();
    if (k) dict[k] = v;
  }
  return dict;
}

// ── Live dictionary test ─────────────────────────────────────
let dictTestTimer = null;
function debouncedDictTest() {
  clearTimeout(dictTestTimer);
  dictTestTimer = setTimeout(runDictTest, 180);
}

async function runDictTest() {
  const input = dictTestIn.value;
  if (!input.trim()) { dictTestOut.textContent = '—'; return; }
  try {
    const result = await invoke('test_dictionary', {
      input,
      dict: collectDict(),
    });
    dictTestOut.textContent = result;
  } catch { dictTestOut.textContent = '—'; }
}

dictTestIn.addEventListener('input', debouncedDictTest);

// ── Save ─────────────────────────────────────────────────────
saveBtn.addEventListener('click', async () => {
  saveBtn.disabled = true;
  setSaveStatus('Saving…', false);

  const config = {
    modelPath:  modelPath.value.trim(),
    hotkey:     hotkeyInput.value.trim() || 'CmdOrCtrl+Shift+Space',
    language:   langSelect.value,
    autostart:  autostartCb.checked,
    dictionary: collectDict(),
  };

  try {
    await invoke('save_config', { newConfig: config });
    setSaveStatus('Saved ✓', false);
    setModelStatus(
      config.modelPath ? '✓ Model path saved — will load on next use' : '',
      config.modelPath ? 'ok' : ''
    );
    setTimeout(() => setSaveStatus('', false), 3000);
  } catch (e) {
    setSaveStatus(`Error: ${e}`, true);
  } finally {
    saveBtn.disabled = false;
  }
});

// ── Helpers ──────────────────────────────────────────────────
function setSaveStatus(msg, isErr) {
  saveStatus.textContent = msg;
  saveStatus.className   = 'save-status' + (isErr ? ' err' : '');
}

function setModelStatus(msg, cls) {
  modelStatus.textContent = msg;
  modelStatus.className   = 'model-status ' + cls;
}

function esc(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
