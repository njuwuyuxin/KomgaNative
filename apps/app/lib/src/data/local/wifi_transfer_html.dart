/// 构建局域网 Wi-Fi 传书内置网页（零外链、支持多文件与文件夹拖拽、实时进度与可选 PIN，LMB-07）。
String buildWifiTransferHtml({required bool pinRequired}) {
  final pinDisplay = pinRequired ? 'block' : 'none';
  return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Yomu · Wi-Fi Transfer</title>
<style>
  :root { color-scheme: light dark; --bg:#f5f6f8; --card:#ffffff; --fg:#181a1f; --muted:#6b7280; --accent:#2563eb; --ok:#16a34a; --err:#dc2626; --border:#e5e7eb; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#101216; --card:#181b22; --fg:#f3f4f6; --muted:#9ca3af; --accent:#60a5fa; --ok:#4ade80; --err:#f87171; --border:#2a2f3a; }
  }
  * { box-sizing:border-box; }
  body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; background:var(--bg); color:var(--fg); padding:24px 16px; }
  .wrap { max-width:680px; margin:0 auto; }
  h1 { margin:0 0 6px; font-size:24px; }
  .sub { margin:0 0 20px; color:var(--muted); font-size:14px; }
  .card { background:var(--card); border:1px solid var(--border); border-radius:16px; padding:20px; margin-bottom:16px; }
  .pin-box { display:$pinDisplay; margin-bottom:16px; }
  .pin-box label { display:block; font-size:13px; color:var(--muted); margin-bottom:6px; }
  .pin-box input { width:160px; padding:10px 12px; font-size:18px; letter-spacing:4px; border:1px solid var(--border); border-radius:10px; background:var(--bg); color:var(--fg); }
  .drop { border:2px dashed var(--border); border-radius:14px; padding:36px 20px; text-align:center; transition:border-color .15s,background .15s; cursor:pointer; }
  .drop.over { border-color:var(--accent); background:rgba(37,99,235,.08); }
  .drop-title { font-size:16px; font-weight:600; margin-bottom:6px; }
  .drop-hint { font-size:13px; color:var(--muted); margin-bottom:16px; }
  .btns { display:flex; gap:10px; justify-content:center; flex-wrap:wrap; }
  button { border:1px solid var(--border); background:var(--accent); color:#fff; border-radius:10px; padding:10px 16px; font-size:14px; font-weight:600; cursor:pointer; }
  button.secondary { background:transparent; color:var(--fg); }
  .list { list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:10px; }
  .item { padding:12px 14px; border:1px solid var(--border); border-radius:12px; }
  .row { display:flex; justify-content:space-between; gap:12px; font-size:14px; margin-bottom:6px; }
  .name { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-weight:500; }
  .status { font-size:12px; color:var(--muted); flex-shrink:0; }
  .status.ok { color:var(--ok); }
  .status.err { color:var(--err); }
  .bar { height:6px; border-radius:999px; background:var(--border); overflow:hidden; }
  .fill { height:100%; width:0; background:var(--accent); transition:width .1s; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Yomu · Wi-Fi 传书</h1>
  <p class="sub">支持拖拽 CBZ / ZIP / 漫画 EPUB / CBT / TAR 压缩包、合集包或整个漫画图片文件夹。</p>
  <div class="card">
    <div class="pin-box" id="pinBox">
      <label for="pinInput">PIN 校验码 / Transfer PIN</label>
      <input id="pinInput" type="text" inputmode="numeric" maxlength="8" placeholder="6-digit PIN" autocomplete="off">
    </div>
    <div class="drop" id="dropZone">
      <div class="drop-title">拖拽文件或文件夹到这里</div>
      <div class="drop-hint">Drop CBZ / ZIP / EPUB / CBT / TAR files or comic folders here</div>
      <div class="btns">
        <button type="button" id="pickFilesBtn">选择压缩包 / Files</button>
        <button type="button" class="secondary" id="pickFolderBtn">选择文件夹 / Folder</button>
      </div>
      <input id="fileInput" type="file" multiple accept=".cbz,.zip,.epub,.cbt,.tar,.pdf,.cbr,.rar,.cb7,.7z" hidden>
      <input id="folderInput" type="file" webkitdirectory multiple hidden>
    </div>
  </div>
  <div class="card">
    <ul class="list" id="queue"></ul>
  </div>
</div>
<script>
const ARCHIVE_RE = /\\.(cbz|zip|epub|cbt|tar|pdf|cbr|rar|cb7|7z)\$/i;
const IMAGE_RE = /\\.(jpe?g|png|webp|gif|bmp|avif|heic|jxl)\$/i;
const SIDECAR_COVER_PRIO = { cover: 0, folder: 1, poster: 2 };
const dropZone = document.getElementById('dropZone');
const fileInput = document.getElementById('fileInput');
const folderInput = document.getElementById('folderInput');
const queueEl = document.getElementById('queue');
const pinInput = document.getElementById('pinInput');

document.getElementById('pickFilesBtn').onclick = () => fileInput.click();
document.getElementById('pickFolderBtn').onclick = () => folderInput.click();
fileInput.onchange = () => { enqueueFiles(Array.from(fileInput.files || [])); fileInput.value = ''; };
folderInput.onchange = () => { enqueueFiles(Array.from(folderInput.files || [])); folderInput.value = ''; };

['dragenter','dragover'].forEach(ev => dropZone.addEventListener(ev, e => { e.preventDefault(); dropZone.classList.add('over'); }));
['dragleave','drop'].forEach(ev => dropZone.addEventListener(ev, e => { e.preventDefault(); dropZone.classList.remove('over'); }));
dropZone.addEventListener('drop', async e => {
  const items = Array.from(e.dataTransfer.items || []);
  const collected = [];
  for (const item of items) {
    const entry = item.webkitGetAsEntry ? item.webkitGetAsEntry() : null;
    if (entry) { await walkEntry(entry, '', collected); }
    else { const f = item.getAsFile && item.getAsFile(); if (f) collected.push({ file: f, relPath: f.name }); }
  }
  await processBatch(collected);
});

async function walkEntry(entry, prefix, out) {
  if (entry.isFile) {
    const file = await new Promise((res, rej) => entry.file(res, rej));
    out.push({ file, relPath: prefix ? prefix + '/' + entry.name : entry.name });
  } else if (entry.isDirectory) {
    const reader = entry.createReader();
    while (true) {
      const batch = await new Promise((res, rej) => reader.readEntries(res, rej));
      if (!batch.length) break;
      for (const child of batch) {
        await walkEntry(child, prefix ? prefix + '/' + entry.name : entry.name, out);
      }
    }
  }
}

async function enqueueFiles(files) {
  const mapped = files.map(f => ({ file: f, relPath: f.webkitRelativePath || f.name }));
  await processBatch(mapped);
}

function createRow(label) {
  const li = document.createElement('li');
  li.className = 'item';
  li.innerHTML = '<div class="row"><span class="name"></span><span class="status">0%</span></div><div class="bar"><div class="fill"></div></div>';
  li.querySelector('.name').textContent = label;
  queueEl.prepend(li);
  return {
    setProgress(p) { li.querySelector('.fill').style.width = p + '%'; li.querySelector('.status').textContent = p + '%'; },
    setDone(msg) { li.querySelector('.fill').style.width = '100%'; const s = li.querySelector('.status'); s.className = 'status ok'; s.textContent = msg; },
    setError(msg) { const s = li.querySelector('.status'); s.className = 'status err'; s.textContent = msg; }
  };
}

function sendStream(url, file, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', url);
    const pin = (pinInput && pinInput.value || '').trim();
    if (pin) xhr.setRequestHeader('X-Yomu-Pin', pin);
    xhr.upload.onprogress = e => { if (e.lengthComputable && onProgress) onProgress(Math.round(e.loaded * 100 / e.total)); };
    xhr.onload = () => {
      try { resolve({ status: xhr.status, data: JSON.parse(xhr.responseText || '{}') }); }
      catch (err) { resolve({ status: xhr.status, data: {} }); }
    };
    xhr.onerror = () => reject(new Error('network_error'));
    xhr.send(file);
  });
}

function sidecarCoverPrio(name) {
  if (!IMAGE_RE.test(name)) return -1;
  const dot = name.lastIndexOf('.');
  const stem = (dot > 0 ? name.slice(0, dot) : name).toLowerCase();
  return Object.prototype.hasOwnProperty.call(SIDECAR_COVER_PRIO, stem) ? SIDECAR_COVER_PRIO[stem] : -1;
}

async function processBatch(entries) {
  const archives = [];
  const archiveDirs = new Set();
  const imageCandidates = [];
  for (const item of entries) {
    const clean = item.relPath.replace(/\\\\/g, '/');
    const parts = clean.split('/').filter(Boolean);
    if (!parts.length || parts.some(p => p.startsWith('.') || p === '__MACOSX')) continue;
    const name = parts[parts.length - 1] || item.file.name;
    const dirPath = parts.length >= 2 ? parts.slice(0, -1).join('/') : '';
    const parent = parts.length >= 2 ? parts[parts.length - 2] : '';
    if (ARCHIVE_RE.test(name)) {
      archives.push({ file: item.file, name, parent, dirPath });
      archiveDirs.add(dirPath);
    } else if (IMAGE_RE.test(name) || name.toLowerCase() === 'comicinfo.xml') {
      imageCandidates.push({ file: item.file, parts, name, dirPath, parent });
    }
  }
  const seriesCovers = new Map();
  const imageFolders = new Map();
  for (const img of imageCandidates) {
    if (archiveDirs.has(img.dirPath)) {
      const prio = sidecarCoverPrio(img.name);
      if (prio >= 0) {
        const prev = seriesCovers.get(img.dirPath);
        if (!prev || prio < prev.prio) {
          seriesCovers.set(img.dirPath, { file: img.file, name: img.name, seriesName: img.parent, prio });
        }
      }
      continue;
    }
    const folder = img.parts.length >= 2 ? img.parts[0] : 'Uploaded Comic';
    const innerPath = img.parts.length >= 2 ? img.parts.slice(1).join('/') : img.name;
    if (!imageFolders.has(folder)) imageFolders.set(folder, []);
    imageFolders.get(folder).push({ file: img.file, innerPath });
  }
  const dirSeriesIds = new Map();
  for (const a of archives) {
    const row = createRow(a.name);
    try {
      const q = '/api/upload?name=' + encodeURIComponent(a.name) + (a.parent ? '&parent=' + encodeURIComponent(a.parent) : '');
      const res = await sendStream(q, a.file, p => row.setProgress(p));
      if (res.status === 401) row.setError('PIN 错误 / Invalid PIN');
      else if (res.status === 429) row.setError('尝试过多，请稍后重试 / Too many attempts');
      else if (res.status === 413) row.setError('文件过大 / File too large');
      else if (res.status >= 200 && res.status < 300 && res.data.ok) {
        row.setDone('已导入 ' + (res.data.importedCount || 1) + ' 册');
        const ids = Array.isArray(res.data.seriesIds) ? res.data.seriesIds : [];
        if (ids.length) {
          if (!dirSeriesIds.has(a.dirPath)) dirSeriesIds.set(a.dirPath, new Set());
          ids.forEach(id => dirSeriesIds.get(a.dirPath).add(id));
        }
      } else row.setError(res.data.error || ('HTTP ' + res.status));
    } catch (e) { row.setError('上传失败'); }
  }
  for (const [dirPath, cov] of seriesCovers.entries()) {
    const ids = Array.from(dirSeriesIds.get(dirPath) || []);
    if (ids.length !== 1) continue;
    const row = createRow(cov.name);
    try {
      const q = '/api/upload-series-cover?seriesId=' + encodeURIComponent(ids[0]) +
        (cov.seriesName ? '&series=' + encodeURIComponent(cov.seriesName) : '') +
        '&name=' + encodeURIComponent(cov.name);
      const res = await sendStream(q, cov.file, p => row.setProgress(p));
      if (res.status === 401) row.setError('PIN 错误 / Invalid PIN');
      else if (res.status === 429) row.setError('尝试过多，请稍后重试 / Too many attempts');
      else if (res.status === 413) row.setError('文件过大 / File too large');
      else if (res.status >= 200 && res.status < 300 && res.data.ok) {
        row.setDone(res.data.applied ? '已设为系列封面' : '已跳过（保留现有封面）');
      } else row.setError(res.data.error || ('HTTP ' + res.status));
    } catch (e) { row.setError('封面上传失败'); }
  }
  for (const [folder, items] of imageFolders.entries()) {
    const row = createRow(folder + ' (' + items.length + ' files)');
    try {
      let failed = false;
      for (let i = 0; i < items.length; i++) {
        const it = items[i];
        const q = '/api/upload-image?folder=' + encodeURIComponent(folder) + '&name=' + encodeURIComponent(it.innerPath);
        const res = await sendStream(q, it.file);
        if (res.status === 401) { row.setError('PIN 错误 / Invalid PIN'); failed = true; break; }
        if (res.status < 200 || res.status >= 300) { row.setError(res.data.error || ('HTTP ' + res.status)); failed = true; break; }
        row.setProgress(Math.round(((i + 1) / items.length) * 90));
      }
      if (!failed) {
        const res = await sendStream('/api/commit-folder?folder=' + encodeURIComponent(folder), new Blob());
        if (res.status >= 200 && res.status < 300 && res.data.ok) row.setDone('已导入目录');
        else row.setError(res.data.error || '导入失败');
      }
    } catch (e) { row.setError('上传失败'); }
  }
}
</script>
</body>
</html>
''';
}
