import {icon} from './icons.js';
const STORAGE_KEY = 'breakapp-theme';
const VALUES = ['light', 'dark', 'system'];

export function initializeTheme() {
  const button = document.querySelector('#theme-toggle');
  const choices = [...document.querySelectorAll('input[name="theme-choice"]')];
  // Il tema predefinito di BreakApp è chiaro, indipendentemente dal sistema.
  // "Come il dispositivo" resta una scelta esplicita dal Profilo.
  let selected = 'light';
  try { selected = localStorage.getItem(STORAGE_KEY) || 'light'; } catch { /* no persistence */ }
  if (!VALUES.includes(selected)) selected = 'light';

  function apply(value) {
    const systemDark = matchMedia('(prefers-color-scheme: dark)').matches;
    const dark = value === 'dark' || (value === 'system' && systemDark);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    for (const meta of document.querySelectorAll('meta[name="theme-color"]')) meta.content = dark ? '#141917' : '#f6f4ef';
    if (button) {
      button.replaceChildren(icon(dark ? 'Sun' : 'Moon'));
      button.setAttribute('aria-label', dark ? 'Passa al tema chiaro' : 'Passa al tema scuro');
      button.title = dark ? 'Tema chiaro' : 'Tema scuro';
    }
    for (const input of choices) input.checked = input.value === value;
  }
  function choose(value) {
    selected = VALUES.includes(value) ? value : 'light';
    try { localStorage.setItem(STORAGE_KEY, selected); } catch { /* optional preference */ }
    apply(selected);
  }
  apply(selected);
  button?.addEventListener('click', () => {
    choose(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
  });
  for (const input of choices) input.addEventListener('change', () => { if (input.checked) choose(input.value); });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if (selected === 'system') apply(selected);
  });
}
