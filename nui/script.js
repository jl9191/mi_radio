let isPlaying = false;

window.addEventListener('message', function (event) {
    let item = event.data;
    if (item.type === "show") {
        if (item.status) {
            document.getElementById('container').classList.remove('hidden');
            setTimeout(() => {
                document.getElementById('container').classList.add('visible');
            }, 10);
        } else {
            document.getElementById('container').classList.remove('visible');
            setTimeout(() => {
                document.getElementById('container').classList.add('hidden');
            }, 300);
        }
    }

    // Recibir actualización de progreso y estado desde client.lua
    if (item.type === "updateProgress") {
        // Si viene un título nuevo (sincronización inicial), mostrarlo
        if (item.title) {
            nowPlaying.innerHTML = `<span><i class="fas fa-music"></i> ${item.title}</span>`;
            isPlaying = true;
            playPauseIcon.className = 'fas fa-pause';
        }

        // Actualizar icono según el estado de pausa
        if (item.isPaused !== undefined) {
            isPlaying = !item.isPaused;
            playPauseIcon.className = isPlaying ? 'fas fa-pause' : 'fas fa-play';
        }

        updateProgressUI(item.currentTime, item.maxDuration);
    }

    if (item.type === "stopProgress") {
        resetUI();
    }

    if (item.type === "pauseProgress") {
        isPlaying = false;
        playPauseIcon.className = 'fas fa-play';
    }

    if (item.type === "resumeProgress") {
        isPlaying = true;
        playPauseIcon.className = 'fas fa-pause';
    }
});

const searchInput = document.getElementById('search-input');
const searchBtn = document.getElementById('search-btn');
const resultsContainer = document.getElementById('results');
const stopBtn = document.getElementById('stop-btn');
const playPauseBtn = document.getElementById('play-pause-btn');
const playPauseIcon = document.getElementById('play-pause-icon');
const forwardBtn = document.getElementById('forward-btn');
const backwardBtn = document.getElementById('backward-btn');
const volumeRange = document.getElementById('volume-range');
const closeBtn = document.getElementById('close-btn');
const nowPlaying = document.getElementById('now-playing');
const progressBar = document.getElementById('progress-bar');
const timeCurrent = document.getElementById('time-current');
const timeTotal = document.getElementById('time-total');

function resetUI() {
    nowPlaying.innerHTML = `<span>Sin reproducir</span>`;
    isPlaying = false;
    playPauseIcon.className = 'fas fa-play';
    progressBar.value = 0;
    timeCurrent.textContent = '0:00';
    timeTotal.textContent = '0:00';
}

// Formatear segundos a m:ss
function formatTime(seconds) {
    if (!seconds || seconds < 0) return "0:00";
    seconds = Math.floor(seconds);
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
}

// Actualizar UI de progreso
function updateProgressUI(currentTime, maxDuration) {
    if (maxDuration && maxDuration > 0) {
        const pct = (currentTime / maxDuration) * 100;
        progressBar.value = pct;
        timeCurrent.textContent = formatTime(currentTime);
        timeTotal.textContent = formatTime(maxDuration);
    } else {
        timeCurrent.textContent = formatTime(currentTime);
        timeTotal.textContent = "0:00";
    }
}

// Cerrar NUI
closeBtn.onclick = function () {
    fetch(`https://${GetParentResourceName()}/close`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({})
    });
};

// Escuchar tecla ESC
window.addEventListener('keyup', function (e) {
    if (e.key === 'Escape') {
        closeBtn.onclick();
    }
});

// Parsear duración "3:03" o "1:20:05" a segundos
function parseDuration(str) {
    if (!str) return 0;
    const parts = str.split(':').map(Number);
    if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    if (parts.length === 2) return parts[0] * 60 + parts[1];
    return 0;
}

// Reproducir música
function playMusic(url, title, duration) {
    // La UI se actualizará cuando llegue el evento de sincronización desde el servidor
    // pero podemos mostrar un aviso inmediato
    nowPlaying.innerHTML = `<span><i class="fas fa-spinner fa-spin"></i> Cargando...</span>`;

    const durationSec = typeof duration === "string" ? parseDuration(duration) : duration;

    fetch(`https://${GetParentResourceName()}/playMusic`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ url: url, title: title, duration: durationSec })
    });
}

// Play/Pause
playPauseBtn.onclick = function () {
    if (isPlaying) {
        fetch(`https://${GetParentResourceName()}/pauseMusic`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({})
        });
    } else {
        fetch(`https://${GetParentResourceName()}/resumeMusic`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({})
        });
    }
};

// Detener música
stopBtn.onclick = function () {
    fetch(`https://${GetParentResourceName()}/stopMusic`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({})
    });
};

// Adelantar 15s
forwardBtn.onclick = function () {
    fetch(`https://${GetParentResourceName()}/seekMusic`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ offset: 15 })
    });
};

// Retroceder 15s
backwardBtn.onclick = function () {
    fetch(`https://${GetParentResourceName()}/seekMusic`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ offset: -15 })
    });
};

// Barra de progreso (seek manual)
let isSeeking = false;
progressBar.addEventListener('mousedown', () => { isSeeking = true; });
progressBar.addEventListener('mouseup', () => {
    isSeeking = false;
    const pct = progressBar.value / 100;
    fetch(`https://${GetParentResourceName()}/seekToPercent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ percent: pct })
    });
});

// Buscar usando la API propia (tubeteca)
async function searchYouTube(query) {
    try {
        const url = `https://tubeteca.com/busqueda/buscar.php?q=${encodeURIComponent(query)}`;
        const res = await fetch(url);
        if (!res.ok) return null;
        const data = await res.json();
        return data;
    } catch (err) {
        console.error("Error en búsqueda:", err);
        return null;
    }
}

// Renderizar resultados
function renderResults(data) {
    resultsContainer.innerHTML = '';
    if (!data || data.length === 0) {
        resultsContainer.innerHTML = '<div class="placeholder-text">No se encontraron resultados</div>';
        return;
    }
    data.forEach(video => {
        const div = document.createElement('div');
        div.className = 'result-item';
        div.innerHTML = `
            <img src="${video.thumbnail}" alt="thumb" onerror="this.src='data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2280%22 height=%2245%22><rect fill=%22%23333%22 width=%2280%22 height=%2245%22/></svg>'">
            <div class="result-info">
                <div class="result-title">${video.title}</div>
                <div class="result-author">${video.duration || ''}</div>
            </div>
            <i class="fas fa-play result-play"></i>
        `;
        div.onclick = () => playMusic(`https://www.youtube.com/watch?v=${video.videoId}`, video.title, video.duration);
        resultsContainer.appendChild(div);
    });
}

// Botón de búsqueda
searchBtn.onclick = async function () {
    const val = searchInput.value.trim();
    if (val === "") return;

    if (val.startsWith("http://") || val.startsWith("https://")) {
        let title = "Link directo";
        try {
            const decoded = decodeURIComponent(val.split('/').pop().split('?')[0]);
            const cleanName = decoded.replace(/\.(ogg|mp3|wav|m4a|flac)$/i, '');
            if (cleanName.length > 3) title = cleanName;
        } catch (e) { }
        playMusic(val, title);
        return;
    }

    resultsContainer.innerHTML = '<div class="placeholder-text"><i class="fas fa-spinner fa-spin"></i> Buscando...</div>';
    const data = await searchYouTube(val);
    if (data) {
        renderResults(data);
    } else {
        resultsContainer.innerHTML = '<div class="placeholder-text"><i class="fas fa-exclamation-triangle"></i> Error al buscar. Prueba con una URL directa.</div>';
    }
};

// Buscar al presionar Enter
searchInput.addEventListener('keypress', function (e) {
    if (e.key === 'Enter') {
        searchBtn.click();
    }
});

// Control de volumen
volumeRange.oninput = function () {
    fetch(`https://${GetParentResourceName()}/setVolume`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ volume: this.value / 100 })
    });
};
