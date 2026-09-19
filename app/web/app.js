(function () {
  "use strict";

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
