// Lightweight 'San Turbo' engine simulator — fast but throttled to avoid resource spikes.
export function createSanTurbo() {
  let running = false;
  let progress = 0;
  let total = 50;
  let timer = null;
  const listeners = { progress: [], log: [], done: [] };

  function emit(name, payload) {
    listeners[name].forEach((cb) => { try { cb(payload); } catch (e) {} });
  }

  function start(opts = {}) {
    if (running) return { running };
    running = true;
    progress = 0;
    total = opts.total || 50;
    emit('log', { level: 'info', message: 'SanTurbo: starting quick pass' });

    // faster but small steps with small idle gaps to keep CPU low
    timer = setInterval(() => {
      progress = Math.min(total, progress + Math.ceil(Math.random() * 6));
      emit('progress', { progress, total });
      if (progress >= total) {
        clearInterval(timer);
        timer = null;
        running = false;
        emit('done', { reclaimed: Math.floor(Math.random() * 512) + 10 });
        emit('log', { level: 'info', message: 'SanTurbo: complete' });
      }
    }, 250);

    return { running };
  }

  function stop() {
    if (!running) return { running };
    running = false;
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    emit('log', { level: 'info', message: 'SanTurbo: stopped' });
    return { running };
  }

  function status() {
    return { running, progress, total };
  }

  function on(event, cb) {
    if (!listeners[event]) throw new Error('unknown event ' + event);
    listeners[event].push(cb);
    return () => {
      const i = listeners[event].indexOf(cb);
      if (i >= 0) listeners[event].splice(i, 1);
    };
  }

  return { start, stop, status, on };
}
