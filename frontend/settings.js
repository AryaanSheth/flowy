/**
 * Flowey Settings UI
 * Plain vanilla JS — no build step, no framework.
 * Tauri commands accessed via window.__TAURI__.core.invoke().
 */

const { invoke } = window.__TAURI__.core;

// ── DOM helpers ───────────────────────────────────────────────
const $ = id => document.getElementById(id);
const $$ = sel => document.querySelectorAll(sel);

// ── Elements ──────────────────────────────────────────────────
const sectionTitle  = $('section-title');
const statusBadge   = $('status-badge');

const modelPath     = $('model-path');
const modelBrowse   = $('model-browse');
const modelStatus   = $('model-status');
const langSelect    = $('language');

const hotkeyInput       = $('hotkey');
const hotkeyRecord      = $('hotkey-record');
const hotkeyReset       = $('hotkey-reset');
const hotkeyHint        = $('hotkey-recording-hint');
const hotkeyPreview     = $('hotkey-preview');
const maxSecsInput      = $('max-secs');

const inputDeviceSelect  = $('input-device');
const refreshDevicesBtn  = $('refresh-devices');

const autostartCb   = $('autostart');
const configPath    = $('config-path');

const dictEntries   = $('dict-entries');
const dictAdd       = $('dict-add');
const dictImport    = $('dict-import');
const dictExport    = $('dict-export');
const dictTestIn    = $('dict-test-input');
const dictTestOut   = $('dict-test-output');

const historyList   = $('history-list');
const historyCount  = $('history-count');
const historyClear  = $('history-clear');

const ollamaEnabled   = $('ollama-enabled');
const ollamaEndpoint  = $('ollama-endpoint');
const ollamaModelSel  = $('ollama-model');
const ollamaModelMan  = $('ollama-model-manual');
const ollamaPrompt    = $('ollama-prompt');
const ollamaCheckBtn  = $('ollama-check');
const ollamaStatus    = $('ollama-status');

const saveBtn       = $('save-btn');
const discardBtn    = $('discard-btn');
const saveStatus    = $('save-status');

// ── Cached config (used for discard) ─────────────────────────
let loadedConfig = null;

// ── Navigation ────────────────────────────────────────────────
const sectionNames = {
  model:      'Model',
  shortcut:   'Shortcut',
  audio:      'Audio',
  output:     'Output',
  dictionary: 'Dictionary',
  ai:         'AI Enhancement',
  history:    'History',
  system:     'System',
};

$$('.nav-item').forEach(btn => {
  btn.addEventListener('click', () => {
    const id = btn.dataset.section;
    $$('.nav-item').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    $$('.panel').forEach(p => p.classList.remove('active'));
    $(`section-${id}`).classList.add('active');
    sectionTitle.textContent = sectionNames[id] ?? id;

    // Lazy-load data for specific sections
    if (id === 'history') refreshHistory();
    if (id === 'audio')   refreshDevices();
    if (id === 'ai' && ollamaEnabled.checked) checkOllama();
  });
});

// ── Load config on window open ────────────────────────────────
async function loadConfig() {
  try {
    const cfg = await invoke('get_config');
    loadedConfig = cfg;
    applyConfig(cfg);
  } catch (e) {
    console.error('Failed to load config:', e);
  }
}

function applyConfig(cfg) {
  modelPath.value        = cfg.modelPath   ?? '';
  langSelect.value       = cfg.language    ?? 'auto';
  hotkeyInput.value      = cfg.hotkey      ?? 'CmdOrCtrl+Shift+Space';
  maxSecsInput.value     = cfg.maxRecordingSecs ?? 60;
  autostartCb.checked    = cfg.autostart   ?? false;

  // Output mode
  const mode = cfg.outputMode ?? 'type';
  const radio = document.querySelector(`input[name="output-mode"][value="${mode}"]`);
  if (radio) radio.checked = true;

  // Input device (populated after device list loads)
  inputDeviceSelect.dataset.pendingValue = cfg.inputDevice ?? '';

  // Ollama
  ollamaEnabled.checked  = cfg.ollamaEnabled ?? false;
  ollamaEndpoint.value   = cfg.ollamaEndpoint ?? 'http://localhost:11434';
  ollamaModelMan.value   = cfg.ollamaModel ?? '';
  ollamaPrompt.value     = cfg.ollamaPrompt ?? '';

  // Dictionary
  dictEntries.innerHTML = '';
  for (const [k, v] of Object.entries(cfg.dictionary ?? {})) {
    addDictRow(k, v);
  }

  // Config path
  if (cfg.configPath) configPath.textContent = cfg.configPath;

  setModelStatus(cfg.modelPath ? '✓ Model path configured' : '', cfg.modelPath ? 'ok' : '');
}

loadConfig();

// ── Status polling ────────────────────────────────────────────
const STATUS_LABELS = {
  Idle:         '● Idle',
  Recording:    '⏺ Recording',
  Transcribing: '⟳ Transcribing',
};
const STATUS_CSS = {
  Idle:         'idle',
  Recording:    'recording',
  Transcribing: 'transcribing',
};

async function pollStatus() {
  try {
    const s = await invoke('get_status');
    const label = STATUS_LABELS[s] ?? s;
    const cls   = STATUS_CSS[s] ?? 'idle';
    if (statusBadge.textContent !== label) {
      statusBadge.textContent = label;
      statusBadge.className   = `status-badge ${cls}`;
    }
  } catch { /* ignore — window might not be focused */ }
}

// Poll every 1.5 s; use visibilitychange to avoid polling when hidden.
let statusInterval = setInterval(pollStatus, 1500);
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    clearInterval(statusInterval);
  } else {
    pollStatus();
    statusInterval = setInterval(pollStatus, 1500);
  }
});
pollStatus();

// ── Model file browse ─────────────────────────────────────────
modelBrowse.addEventListener('click', async () => {
  try {
    const selected = await invoke('browse_model_file');
    if (selected) {
      modelPath.value = selected;
      setModelStatus('✓ Path updated — save to apply', 'ok');
    }
  } catch (e) { console.error('File picker error:', e); }
});

// ── Audio devices ─────────────────────────────────────────────
async function refreshDevices() {
  try {
    const devices = await invoke('list_audio_devices');
    inputDeviceSelect.innerHTML = '';
    devices.forEach((d, i) => {
      const opt = document.createElement('option');
      opt.value = d;
      opt.textContent = d === '' ? 'System default' : d;
      inputDeviceSelect.appendChild(opt);
    });
    // Restore pending value
    const pending = inputDeviceSelect.dataset.pendingValue ?? '';
    inputDeviceSelect.value = pending;
  } catch (e) { console.error('Device list error:', e); }
}

refreshDevicesBtn.addEventListener('click', refreshDevices);

// ── Ollama ────────────────────────────────────────────────────
async function checkOllama() {
  const endpoint = ollamaEndpoint.value.trim() || 'http://localhost:11434';
  setOllamaStatus('Checking…', null);
  try {
    const result = await invoke('check_ollama', { endpoint });
    if (!result.reachable) {
      setOllamaStatus(result.error || 'Cannot reach Ollama', 'err');
      ollamaModelSel.innerHTML = '<option value="">—</option>';
      return;
    }
    if (result.error) {
      setOllamaStatus(`Connected, but: ${result.error}`, 'warn');
    } else {
      setOllamaStatus(`✓ Connected · ${result.models.length} model${result.models.length === 1 ? '' : 's'} installed`, 'ok');
    }
    // Populate dropdown
    ollamaModelSel.innerHTML = '';
    const placeholder = document.createElement('option');
    placeholder.value = '';
    placeholder.textContent = '— Select model —';
    ollamaModelSel.appendChild(placeholder);
    result.models.forEach(m => {
      const o = document.createElement('option');
      o.value = m;
      o.textContent = m;
      ollamaModelSel.appendChild(o);
    });
    // If current manual value matches an installed model, pre-select it
    if (ollamaModelMan.value && result.models.includes(ollamaModelMan.value)) {
      ollamaModelSel.value = ollamaModelMan.value;
    }
  } catch (e) {
    setOllamaStatus(`Error: ${e}`, 'err');
  }
}

ollamaCheckBtn.addEventListener('click', checkOllama);

// Selecting from dropdown updates the manual field.
ollamaModelSel.addEventListener('change', () => {
  if (ollamaModelSel.value) ollamaModelMan.value = ollamaModelSel.value;
});

function setOllamaStatus(msg, cls) {
  ollamaStatus.textContent = msg;
  ollamaStatus.className   = cls ? `inline-status ${cls}` : 'inline-status';
}

// ── Hotkey recorder ───────────────────────────────────────────
let recordingHotkey = false;
const MODIFIER_KEYS = new Set(['Meta','Control','Alt','Shift']);
const KEY_MAP = { ' ': 'Space', 'ArrowUp': 'Up', 'ArrowDown': 'Down',
                  'ArrowLeft': 'Left', 'ArrowRight': 'Right' };

hotkeyRecord.addEventListener('click', () => {
  if (recordingHotkey) {
    stopHotkeyRecord();
  } else {
    startHotkeyRecord();
  }
});

hotkeyReset.addEventListener('click', () => {
  hotkeyInput.value = 'CmdOrCtrl+Shift+Space';
  stopHotkeyRecord();
});

function startHotkeyRecord() {
  recordingHotkey = true;
  hotkeyRecord.textContent = 'Cancel';
  hotkeyHint.style.display = 'block';
  hotkeyPreview.textContent = '';
  window.addEventListener('keydown', captureHotkey, { capture: true });
}

function stopHotkeyRecord() {
  recordingHotkey = false;
  hotkeyRecord.textContent = 'Change';
  hotkeyHint.style.display = 'none';
  window.removeEventListener('keydown', captureHotkey, { capture: true });
}

function captureHotkey(e) {
  e.preventDefault();
  e.stopPropagation();

  if (MODIFIER_KEYS.has(e.key)) {
    // Show partial combo while only modifiers held
    hotkeyPreview.textContent = buildPartialCombo(e);
    return;
  }

  const combo = buildCombo(e);
  hotkeyInput.value = combo;
  stopHotkeyRecord();
}

function buildPartialCombo(e) {
  const parts = [];
  if (e.metaKey)    parts.push('CmdOrCtrl');
  else if (e.ctrlKey) parts.push('CmdOrCtrl');
  if (e.altKey)     parts.push('Alt');
  if (e.shiftKey)   parts.push('Shift');
  return parts.join('+') + (parts.length ? '+…' : '');
}

function buildCombo(e) {
  const parts = [];
  if (e.metaKey || e.ctrlKey) parts.push('CmdOrCtrl');
  if (e.altKey)   parts.push('Alt');
  if (e.shiftKey) parts.push('Shift');
  const key = KEY_MAP[e.key] ?? (e.key.length === 1 ? e.key.toUpperCase() : e.key);
  parts.push(key);
  return parts.join('+');
}

// ── Dictionary ────────────────────────────────────────────────
function addDictRow(key = '', value = '') {
  const row = document.createElement('div');
  row.className = 'dict-row';
  row.innerHTML = `
    <input type="text" class="dict-key"   value="${esc(key)}"   placeholder="word" spellcheck="false" />
    <span class="dict-arrow-label">→</span>
    <input type="text" class="dict-val"   value="${esc(value)}" placeholder="replacement" spellcheck="false" />
    <button class="dict-del" title="Remove entry">✕</button>
  `;
  row.querySelector('.dict-del').addEventListener('click', () => { row.remove(); debounceTest(); });
  row.addEventListener('input', debounceTest);
  dictEntries.appendChild(row);
  return row;
}

dictAdd.addEventListener('click', () => {
  const row = addDictRow();
  row.querySelector('.dict-key').focus();
});

function collectDict() {
  const dict = {};
  for (const row of dictEntries.querySelectorAll('.dict-row')) {
    const k = row.querySelector('.dict-key').value.trim().toLowerCase();
    const v = row.querySelector('.dict-val').value.trim();
    if (k) dict[k] = v;
  }
  return dict;
}

// Import / Export
dictImport.addEventListener('click', () => {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.json';
  input.onchange = async e => {
    try {
      const text = await e.target.files[0].text();
      const data = JSON.parse(text);
      if (typeof data !== 'object' || Array.isArray(data)) throw new Error('Expected a JSON object');
      dictEntries.innerHTML = '';
      for (const [k, v] of Object.entries(data)) addDictRow(k, String(v));
      debounceTest();
    } catch (err) { alert('Import failed: ' + err.message); }
  };
  input.click();
});

dictExport.addEventListener('click', () => {
  const blob = new Blob([JSON.stringify(collectDict(), null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'flowey-dictionary.json';
  a.click();
});

// Live test
let testTimer = null;
function debounceTest() { clearTimeout(testTimer); testTimer = setTimeout(runDictTest, 200); }

async function runDictTest() {
  const input = dictTestIn.value;
  if (!input.trim()) { dictTestOut.textContent = '—'; return; }
  try {
    dictTestOut.textContent = await invoke('test_dictionary', { input, dict: collectDict() });
  } catch { dictTestOut.textContent = '—'; }
}

dictTestIn.addEventListener('input', debounceTest);

// ── History ───────────────────────────────────────────────────
async function refreshHistory() {
  try {
    const items = await invoke('get_history');
    historyCount.textContent = `${items.length} ${items.length === 1 ? 'entry' : 'entries'}`;
    if (!items.length) {
      historyList.innerHTML = '<p class="empty-state">No transcriptions yet. Hold the hotkey and speak!</p>';
      return;
    }
    historyList.innerHTML = '';
    items.forEach(text => {
      const div = document.createElement('div');
      div.className = 'history-item';
      div.innerHTML = `
        <span class="history-text">${esc(text)}</span>
        <button class="history-copy" title="Copy to clipboard">Copy</button>
      `;
      div.querySelector('.history-copy').addEventListener('click', async () => {
        try {
          // Use the clipboard output mode command to copy via Rust
          await navigator.clipboard.writeText(text);
          div.querySelector('.history-copy').textContent = '✓';
          setTimeout(() => { div.querySelector('.history-copy').textContent = 'Copy'; }, 1500);
        } catch {
          div.querySelector('.history-copy').textContent = '✕';
        }
      });
      historyList.appendChild(div);
    });
  } catch (e) { console.error('History error:', e); }
}

historyClear.addEventListener('click', async () => {
  if (!confirm('Clear all transcription history?')) return;
  await invoke('clear_history');
  refreshHistory();
});

// ── Save ──────────────────────────────────────────────────────
saveBtn.addEventListener('click', async () => {
  saveBtn.disabled = true;
  setSaveStatus('Saving…', null);

  const outputMode = (() => {
    const r = document.querySelector('input[name="output-mode"]:checked');
    return r ? r.value : 'type';
  })();

  const newConfig = {
    modelPath:         modelPath.value.trim(),
    hotkey:            hotkeyInput.value.trim() || 'CmdOrCtrl+Shift+Space',
    language:          langSelect.value,
    autostart:         autostartCb.checked,
    dictionary:        collectDict(),
    inputDevice:       inputDeviceSelect.value || null,
    outputMode,
    maxRecordingSecs:  parseInt(maxSecsInput.value, 10) || 60,
    historySize:       loadedConfig?.historySize ?? 20,
    ollamaEnabled:     ollamaEnabled.checked,
    ollamaEndpoint:    ollamaEndpoint.value.trim() || 'http://localhost:11434',
    ollamaModel:       (ollamaModelMan.value || ollamaModelSel.value || 'llama3.2:3b').trim(),
    ollamaPrompt:      ollamaPrompt.value.trim() || loadedConfig?.ollamaPrompt || '',
  };

  try {
    await invoke('save_config', { newConfig });
    loadedConfig = newConfig;
    setSaveStatus('Saved ✓', 'ok');
    setModelStatus(newConfig.modelPath ? '✓ Model path saved' : '', newConfig.modelPath ? 'ok' : '');
    setTimeout(() => setSaveStatus('', null), 3000);
  } catch (e) {
    setSaveStatus(`Error: ${e}`, 'err');
  } finally {
    saveBtn.disabled = false;
  }
});

// Discard: reload from cached config
discardBtn.addEventListener('click', () => {
  if (loadedConfig) {
    applyConfig(loadedConfig);
    setSaveStatus('Changes discarded', null);
    setTimeout(() => setSaveStatus('', null), 2000);
  }
});

// ── Helpers ───────────────────────────────────────────────────
function setSaveStatus(msg, cls) {
  saveStatus.textContent = msg;
  saveStatus.className   = cls ? `save-status ${cls}` : 'save-status';
}

function setModelStatus(msg, cls) {
  modelStatus.textContent = msg;
  modelStatus.className   = cls ? `inline-status ${cls}` : 'inline-status';
}

function esc(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
