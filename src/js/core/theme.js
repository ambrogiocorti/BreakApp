const STORAGE_KEY = 'breakapp-theme';

export function initializeTheme() {
  const button = document.querySelector('#theme-toggle');
  if (!button) return;
  let selected = 'system';
  try { selected = localStorage.getItem(STORAGE_KEY) || 'system'; } catch { /* no persistence */ }

  function apply(value) {
    const systemDark = matchMedia('(prefers-color-scheme: dark)').matches;
    const dark = value === 'dark' || (value === 'system' && systemDark);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    button.textContent = dark ? '☀' : '☾';
    button.setAttribute('aria-label', dark ? 'Passa al tema chiaro' : 'Passa al tema scuro');
    button.title = dark ? 'Tema chiaro' : 'Tema scuro';
  }
  apply(selected);
  button.addEventListener('click', () => {
    selected = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    try { localStorage.setItem(STORAGE_KEY, selected); } catch { /* optional preference */ }
    apply(selected);
  });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if (selected === 'system') apply(selected);
  });
}
