(function () {
  "use strict";

  var paths = {
    back: 'M15 5l-7 7 7 7', refresh: 'M20 7v5h-5M20 12a8 8 0 1 0-2 5M20 7l-3-3',
    search: 'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',
    list: 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
    grid: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
    folder: 'M3 7V5a1 1 0 0 1 1-1h5l2 3h9a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z',
    file: 'M5 3h9l5 5v13H5zM14 3v6h5M8 13h8M8 17h6',
    image: 'M3 3h18v18H3zM3 17l6-6 4 4 3-3 5 5M15 7h.01',
    video: 'M3 5h13v14H3zM16 10l5-3v10l-5-3',
    audio: 'M9 18V5l11-2v13M9 8l11-2M9 18a3 3 0 1 1-3-3h3M20 16a3 3 0 1 1-3-3h3',
    code: 'M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16',
    archive: 'M4 3h16v18H4zM10 3v3h4v3h-4v3h4v3h-4v4h4v-4',
    sheet: 'M4 3h16v18H4zM4 9h16M4 15h16M10 9v12',
    download: 'M12 3v12M7 10l5 5 5-5M4 16v5h16v-5',
    trash: 'M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7',
    open: 'M9 5l7 7-7 7'
  };
  function icon(name) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + (paths[name] || paths.file) + '"/></svg>';
  }
  document.querySelectorAll('[data-icon]').forEach(function (el) { el.innerHTML = icon(el.dataset.icon); });
  var rows = Array.from(document.querySelectorAll('tbody tr')).filter(function (row) { return row.querySelector('.name'); });
  rows.forEach(function (row) {
    var link = row.querySelector('.name a');
    var folder = link.getAttribute('href').indexOf('?p=') === 0;
    var ext = link.textContent.split('.').pop().toLowerCase();
    var kind = folder ? 'folder' : /^(png|jpg|jpeg|gif|svg|webp|ico|heic)$/.test(ext) ? 'image' : /^(mp4|mkv|mov|webm|avi)$/.test(ext) ? 'video' : /^(mp3|wav|flac|ogg|m4a)$/.test(ext) ? 'audio' : /^(zip|rar|7z|gz|tar)$/.test(ext) ? 'archive' : /^(csv|xlsx|xls)$/.test(ext) ? 'sheet' : /^(js|ts|json|html|css|py|ps1|sh|xml)$/.test(ext) ? 'code' : 'file';
    row.dataset.name = link.textContent.toLowerCase();
    var name = document.createElement('span'); name.className = 'filename'; name.textContent = link.textContent;
    link.textContent = ''; var mark = document.createElement('span'); mark.className = 'file-icon kind-' + kind; mark.innerHTML = icon(kind);
    link.append(mark, name);
    var info = document.createElement('small'); info.className = 'file-summary'; info.textContent = folder ? 'Folder' : row.querySelector('.size').textContent + ' · ' + row.querySelector('.type').textContent;
    name.appendChild(info);
    row.querySelectorAll('.action').forEach(function (action) {
      var label = action.textContent; action.title = label; action.setAttribute('aria-label', label + ' ' + row.dataset.name);
      action.innerHTML = icon(action.classList.contains('danger') ? 'trash' : folder ? 'open' : 'download');
    });
  });
  var crumbs = document.querySelectorAll('.pathbar a');
  var back = document.getElementById('backButton');
  if (back && crumbs.length > 1) { back.disabled = false; back.onclick = function () { location.href = crumbs[crumbs.length - 2].href; }; }
  var refresh = document.getElementById('refreshButton'); if (refresh) refresh.onclick = function () { location.reload(); };
  var search = document.getElementById('searchInput');
  if (search) search.addEventListener('input', function () {
    var count = 0; rows.forEach(function (row) { row.hidden = !row.dataset.name.includes(search.value.toLowerCase()); if (!row.hidden) count++; });
    document.getElementById('itemCount').textContent = count + ' item';
    document.getElementById('noResults').hidden = count > 0 || !search.value;
  });
  function setView(view) {
    document.body.dataset.view = view;
    document.getElementById('listView').setAttribute('aria-pressed', view === 'list');
    document.getElementById('gridView').setAttribute('aria-pressed', view === 'grid');
    try { localStorage.setItem('wintunnel-view', view); } catch (_) {}
  }
  if (document.getElementById('listView')) {
    document.getElementById('listView').onclick = function () { setView('list'); };
    document.getElementById('gridView').onclick = function () { setView('grid'); };
    var density = document.getElementById('density');
    density.onchange = function () { document.body.dataset.density = density.value; try { localStorage.setItem('wintunnel-density', density.value); } catch (_) {} };
    try { setView(localStorage.getItem('wintunnel-view') || 'list'); density.value = localStorage.getItem('wintunnel-density') || (innerWidth < 700 ? 'compact' : 'comfortable'); } catch (_) {}
    density.onchange();
  }

  var section = document.querySelector(".upload");
  if (!section) return;

  var input = document.getElementById("fileInput");
  var button = document.getElementById("uploadButton");
  var status = document.getElementById("uploadStatus");
  var progress = document.getElementById("uploadProgress");
  var bar = document.getElementById("uploadBar");

  button.addEventListener("click", function () {
    var file = input.files[0];
    if (!file) {
      status.textContent = "Pilih file terlebih dahulu.";
      return;
    }

    button.disabled = true;
    button.textContent = "Mengupload...";
    progress.style.display = "block";
    status.textContent = file.name;

    var xhr = new XMLHttpRequest();
    var folder = section.getAttribute("data-upload-path") || "";
    xhr.open("PUT", "/upload?p=" + folder + "&name=" + encodeURIComponent(file.name));
    xhr.upload.onprogress = function (event) {
      if (!event.lengthComputable) return;
      var percent = Math.round(event.loaded / event.total * 100);
      bar.style.width = percent + "%";
      status.textContent = file.name + " - " + percent + "%";
    };
    xhr.onload = function () {
      if (xhr.status >= 200 && xhr.status < 300) {
        bar.style.width = "100%";
        status.textContent = "Upload selesai.";
        setTimeout(function () { location.reload(); }, 350);
        return;
      }
      button.disabled = false;
      button.textContent = "Coba lagi";
      status.textContent = xhr.responseText || "Upload gagal.";
    };
    xhr.onerror = function () {
      button.disabled = false;
      button.textContent = "Coba lagi";
      status.textContent = "Upload gagal. Periksa koneksi lalu coba lagi.";
    };
    xhr.send(file);
  });
}());
