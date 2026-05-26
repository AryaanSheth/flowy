/**
 * Flowey Settings UI
 * Plain vanilla JS — no build step, no framework.
 */

const { invoke } = window.__TAURI__.core;

// ── DOM helpers ────────────────────────────────────────────────
const $ = id => document.getElementById(id);
const $$ = sel => document.querySelectorAll(sel);

// ── Elements ───────────────────────────────────────────────────
const sectionTitle      = $('section-title');
const statusBadge       = $('status-badge');

const hotkeyInput       = $('hotkey');
const hotkeyRecord      = $('hotkey-record');
const hotkeyReset       = $('hotkey-reset');
const hotkeyHint        = $('hotkey-recording-hint');
const hotkeyPreview     = $('hotkey-preview');
const maxSecsInput      = $('max-secs');

const inputDeviceSelect = $('input-device');
const refreshDevicesBtn = $('refresh-devices');

const autostartCb       = $('autostart');
const configPath        = $('config-path');

const dictEntries       = $('dict-entries');
const dictAdd           = $('dict-add');
const dictImport        = $('dict-import');
const dictExport        = $('dict-export');
const dictTestIn        = $('dict-test-input');
const dictTestOut       = $('dict-test-output');

const historyList       = $('history-list');
const historyCount      = $('history-count');
const historyClear      = $('history-clear');

const ollamaEnabled     = $('ollama-enabled');
const ollamaEndpoint    = $('ollama-endpoint');
const ollamaModelSel    = $('ollama-model');
const ollamaPrompt      = $('ollama-prompt');
const ollamaCheckBtn    = $('ollama-check');
const ollamaStatus      = $('ollama-status');

const saveBtn           = $('save-btn');
const discardBtn        = $('discard-btn');
const saveStatus        = $('save-status');

const recOverlay        = $('rec-overlay');
const recLabel          = $('rec-label');
const recHotkeyHint     = $('rec-hotkey-hint');

const pttBtn            = $('ptt-btn');
const pttLabel          = $('ptt-label');
const permAccessibility = $('perm-accessibility');
const permSpeech        = $('perm-speech');

// ── Cached config ──────────────────────────────────────────────
let loadedConfig = null;

// ── Navigation ─────────────────────────────────────────────────
const sectionNames = {
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

    if (id === 'history') refreshHistory();
    if (id === 'audio')   refreshDevices();
    if (id === 'ai' && ollamaEnabled.checked) checkOllama();
  });
});

// ── Load config ────────────────────────────────────────────────
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
  hotkeyInput.value  = cfg.hotkey      ?? 'CmdOrCtrl+Shift+Space';
  maxSecsInput.value = cfg.maxRecordingSecs ?? 60;
  autostartCb.checked = cfg.autostart  ?? false;

  // Output mode
  const mode = cfg.outputMode ?? 'type';
  const radio = document.querySelector(`input[name="output-mode"][value="${mode}"]`);
  if (radio) radio.checked = true;

  // Input device (populated after device list loads)
  inputDeviceSelect.dataset.pendingValue = cfg.inputDevice ?? '';

  // Ollama
  ollamaEnabled.checked = cfg.ollamaEnabled ?? false;
  ollamaEndpoint.value  = cfg.ollamaEndpoint ?? 'http://localhost:11434';
  ollamaModelSel.dataset.savedModel = cfg.ollamaModel ?? '';
  ollamaPrompt.value    = cfg.ollamaPrompt ?? '';

  // Dictionary
  dictEntries.innerHTML = '';
  for (const [k, v] of Object.entries(cfg.dictionary ?? {})) {
    addDictRow(k, v);
  }

  if (cfg.configPath) configPath.textContent = cfg.configPath;
}

loadConfig();

// ── Permissions check ──────────────────────────────────────────
async function checkPermissions() {
  try {
    const p = await invoke('check_permissions');
    permAccessibility.style.display = p.accessibility ? 'none' : '';
    permSpeech.style.display        = p.speech        ? 'none' : '';
  } catch { /* ignore */ }
}
checkPermissions();

// Re-check whenever the window becomes visible (user may have just
// granted access in System Settings).
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) checkPermissions();
});

// "Open Accessibility settings" link
$('perm-open-accessibility')?.addEventListener('click', e => {
  e.preventDefault();
  // shell open the pane directly
  invoke('start_recording').catch(() => {}); // no-op, just to show intent
  window.open(
    'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    '_blank'
  );
});

// ── Status (badge + overlay) ───────────────────────────────────
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

function applyStatus(s) {
  // Badge
  const label = STATUS_LABELS[s] ?? s;
  const cls   = STATUS_CSS[s]    ?? 'idle';
  statusBadge.textContent = label;
  statusBadge.className   = `status-badge ${cls}`;

  // Overlay
  if (s === 'Recording') {
    recLabel.textContent = 'Recording…';
    recOverlay.classList.remove('transcribing');
    recOverlay.removeAttribute('hidden');
  } else if (s === 'Transcribing') {
    recLabel.textContent = 'Processing…';
    recOverlay.classList.add('transcribing');
    recOverlay.removeAttribute('hidden');
  } else {
    recOverlay.setAttribute('hidden', '');
    recOverlay.classList.remove('transcribing');
  }
}

// Instant push from Rust via Tauri event
if (window.__TAURI__?.event) {
  window.__TAURI__.event.listen('flowey:status', ({ payload }) => {
    applyStatus(payload);
  });
}

// Fallback polling (catches state on page load / if events are missed)
async function pollStatus() {
  try {
    const s = await invoke('get_status');
    applyStatus(s);
  } catch { /* ignore */ }
}

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

// Show current hotkey in the overlay hint
function updateHotkeyHint() {
  recHotkeyHint.textContent = hotkeyInput.value || 'hotkey';
}
updateHotkeyHint();
hotkeyInput.addEventListener('change', updateHotkeyHint);

// ── Push-to-talk button ────────────────────────────────────────
let pttActive = false;

async function pttStart() {
  if (pttActive) return;
  pttActive = true;
  pttBtn.classList.add('recording');
  pttLabel.textContent = 'Recording…';
  try { await invoke('start_recording'); } catch(e) { console.error(e); pttStop(); }
}

async function pttStop() {
  if (!pttActive) return;
  pttActive = false;
  pttBtn.classList.remove('recording');
  pttLabel.textContent = 'Hold to Record';
  try { await invoke('stop_recording'); } catch { /* ignore */ }
}

pttBtn.addEventListener('mousedown', e => { e.preventDefault(); pttStart(); });
pttBtn.addEventListener('mouseup',   () => pttStop());
pttBtn.addEventListener('mouseleave',() => { if (pttActive) pttStop(); });
// Touch support
pttBtn.addEventListener('touchstart', e => { e.preventDefault(); pttStart(); }, { passive: false });
pttBtn.addEventListener('touchend',   () => pttStop());

// When a status event says we went Idle (pipeline done), reset button label
if (window.__TAURI__?.event) {
  window.__TAURI__.event.listen('flowey:status', ({ payload }) => {
    if (payload === 'Idle' && !pttActive) {
      pttLabel.textContent = 'Hold to Record';
      pttBtn.classList.remove('recording');
    }
  });
}

// ── Audio devices ──────────────────────────────────────────────
async function refreshDevices() {
  try {
    const devices = await invoke('list_audio_devices');
    inputDeviceSelect.innerHTML = '';
    devices.forEach(d => {
      const opt = document.createElement('option');
      opt.value = d;
      opt.textContent = d === '' ? 'System default' : d;
      inputDeviceSelect.appendChild(opt);
    });
    inputDeviceSelect.value = inputDeviceSelect.dataset.pendingValue ?? '';
  } catch (e) { console.error('Device list error:', e); }
}

refreshDevicesBtn.addEventListener('click', refreshDevices);

// ── Ollama ─────────────────────────────────────────────────────
async function checkOllama() {
  const endpoint = ollamaEndpoint.value.trim() || 'http://localhost:11434';
  setOllamaStatus('Checking…', null);
  try {
    const result = await invoke('check_ollama', { endpoint });
    if (!result.reachable) {
      setOllamaStatus(result.error || 'Cannot reach Ollama', 'err');
      ollamaModelSel.innerHTML = '<option value="">— connect Ollama to see models —</option>';
      return;
    }
    if (result.error) {
      setOllamaStatus(`Connected, but: ${result.error}`, 'warn');
    } else {
      setOllamaStatus(
        `✓ Connected · ${result.models.length} model${result.models.length === 1 ? '' : 's'}`,
        'ok'
      );
    }
    ollamaModelSel.innerHTML = '';
    if (!result.models.length) {
      const none = document.createElement('option');
      none.value = '';
      none.textContent = '— no models installed —';
      ollamaModelSel.appendChild(none);
    } else {
      result.models.forEach(m => {
        const o = document.createElement('option');
        o.value = m;
        o.textContent = m;
        ollamaModelSel.appendChild(o);
      });
      const saved = ollamaModelSel.dataset.savedModel ?? '';
      if (saved && result.models.includes(saved)) {
        ollamaModelSel.value = saved;
      }
    }
  } catch (e) {
    setOllamaStatus(`Error: ${e}`, 'err');
  }
}

ollamaCheckBtn.addEventListener('click', checkOllama);

function setOllamaStatus(msg, cls) {
  ollamaStatus.textContent = msg;
  ollamaStatus.className   = cls ? `inline-status ${cls}` : 'inline-status';
}

// ── Hotkey recorder ────────────────────────────────────────────
let recordingHotkey = false;
const MODIFIER_KEYS = new Set(['Meta', 'Control', 'Alt', 'Shift']);
const KEY_MAP = {
  ' ': 'Space', ArrowUp: 'Up', ArrowDown: 'Down',
  ArrowLeft: 'Left', ArrowRight: 'Right'
};

hotkeyRecord.addEventListener('click', () => {
  if (recordingHotkey) stopHotkeyRecord();
  else                 startHotkeyRecord();
});

hotkeyReset.addEventListener('click', () => {
  hotkeyInput.value = 'CmdOrCtrl+Shift+Space';
  stopHotkeyRecord();
});

function startHotkeyRecord() {
  recordingHotkey = true;
  hotkeyRecord.textContent = 'Cancel';
  hotkeyHint.style.display = 'flex';
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
  e.preventDefault(); e.stopPropagation();
  if (MODIFIER_KEYS.has(e.key)) {
    hotkeyPreview.textContent = buildPartialCombo(e);
    return;
  }
  hotkeyInput.value = buildCombo(e);
  stopHotkeyRecord();
}

function buildPartialCombo(e) {
  const parts = [];
  if (e.metaKey || e.ctrlKey) parts.push('CmdOrCtrl');
  if (e.altKey)   parts.push('Alt');
  if (e.shiftKey) parts.push('Shift');
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

// ── Dictionary ─────────────────────────────────────────────────
function addDictRow(key = '', value = '') {
  const row = document.createElement('div');
  row.className = 'dict-row';
  row.innerHTML = `
    <input type="text" class="dict-key"   value="${esc(key)}"   placeholder="word"        spellcheck="false" />
    <span class="dict-arrow-label">→</span>
    <input type="text" class="dict-val"   value="${esc(value)}" placeholder="replacement" spellcheck="false" />
    <button class="dict-del" title="Remove">✕</button>
  `;
  row.querySelector('.dict-del').addEventListener('click', () => { row.remove(); debounceTest(); });
  row.addEventListener('input', debounceTest);
  dictEntries.appendChild(row);
  return row;
}

dictAdd.addEventListener('click', () => addDictRow().querySelector('.dict-key').focus());

function collectDict() {
  const dict = {};
  for (const row of dictEntries.querySelectorAll('.dict-row')) {
    const k = row.querySelector('.dict-key').value.trim().toLowerCase();
    const v = row.querySelector('.dict-val').value.trim();
    if (k) dict[k] = v;
  }
  return dict;
}

dictImport.addEventListener('click', () => {
  const input = document.createElement('input');
  input.type = 'file'; input.accept = '.json';
  input.onchange = async e => {
    try {
      const data = JSON.parse(await e.target.files[0].text());
      if (typeof data !== 'object' || Array.isArray(data)) throw new Error('Expected a JSON object');
      dictEntries.innerHTML = '';
      for (const [k, v] of Object.entries(data)) addDictRow(k, String(v));
      debounceTest();
    } catch (err) { alert('Import failed: ' + err.message); }
  };
  input.click();
});

dictExport.addEventListener('click', () => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(
    new Blob([JSON.stringify(collectDict(), null, 2)], { type: 'application/json' })
  );
  a.download = 'flowey-dictionary.json';
  a.click();
});

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

// ── History ────────────────────────────────────────────────────
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
        <button class="history-copy" title="Copy">Copy</button>
      `;
      div.querySelector('.history-copy').addEventListener('click', async () => {
        try {
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

// ── Save ───────────────────────────────────────────────────────
saveBtn.addEventListener('click', async () => {
  saveBtn.disabled = true;
  setSaveStatus('Saving…', null);

  const outputMode = (() => {
    const r = document.querySelector('input[name="output-mode"]:checked');
    return r ? r.value : 'type';
  })();

  const newConfig = {
    hotkey:           hotkeyInput.value.trim() || 'CmdOrCtrl+Shift+Space',
    autostart:        autostartCb.checked,
    dictionary:       collectDict(),
    inputDevice:      inputDeviceSelect.value || null,
    outputMode,
    maxRecordingSecs: parseInt(maxSecsInput.value, 10) || 60,
    historySize:      loadedConfig?.historySize ?? 20,
    ollamaEnabled:    ollamaEnabled.checked,
    ollamaEndpoint:   ollamaEndpoint.value.trim() || 'http://localhost:11434',
    ollamaModel:      ollamaModelSel.value || loadedConfig?.ollamaModel || '',
    ollamaPrompt:     ollamaPrompt.value.trim() || loadedConfig?.ollamaPrompt || '',
  };

  try {
    await invoke('save_config', { newConfig });
    loadedConfig = newConfig;
    setSaveStatus('Saved ✓', 'ok');
    setTimeout(() => setSaveStatus('', null), 3000);
  } catch (e) {
    setSaveStatus(`Error: ${e}`, 'err');
  } finally {
    saveBtn.disabled = false;
  }
});

discardBtn.addEventListener('click', () => {
  if (loadedConfig) {
    applyConfig(loadedConfig);
    setSaveStatus('Changes discarded', null);
    setTimeout(() => setSaveStatus('', null), 2000);
  }
});

// ── Helpers ────────────────────────────────────────────────────
function setSaveStatus(msg, cls) {
  saveStatus.textContent = msg;
  saveStatus.className   = cls ? `save-status ${cls}` : 'save-status';
}

function esc(str) {
  return String(str)
    .replace(/&/g, '&amp;').replace(/"/g, '&quot;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
