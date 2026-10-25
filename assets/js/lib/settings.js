const PREFIX = "lotus:";

export function loadAll() {
  const values = {};

  for (const [key, json] of Object.entries(localStorage)) {
    if (key.startsWith(PREFIX)) values[key] = JSON.parse(json);
  }

  return values;
}

export function load(key) {
  const json = localStorage.getItem(PREFIX + key);

  if (json) return JSON.parse(json);
}

// The lists' views as the viewer last chose them (a gallery or a table),
// for the server to render them so from the first frame.
export function listViews() {
  return {
    queries: load("queries_view"),
    dashboards: load("dashboards_view"),
    schedules: load("schedules_view"),
  };
}

export function store(key, value) {
  localStorage.setItem(PREFIX + key, JSON.stringify(value));
}
