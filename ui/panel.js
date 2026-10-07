const start = document.getElementById("start");
const stop = document.getElementById("stop");
const search = document.getElementById("search");
let allPlaces = [];

function renderPlaces() {
    const query = search.value.toLocaleLowerCase();
    const places = query ? allPlaces.filter(name => name.toLocaleLowerCase().includes(query)) : allPlaces;
    document.getElementById("count").textContent = query ? places.length + " / " + allPlaces.length : allPlaces.length;
    const empty = document.getElementById("empty");
    empty.hidden = places.length > 0;
    empty.textContent = query ? "No matching blorps." : "Start recording, then look at or locate identified items.";
    const list = document.getElementById("places");
    list.replaceChildren();
    for (const name of places) {
        const row = document.createElement("li");
        row.className = "place-entry";
        const label = document.createElement("span");
        label.className = "place-name";
        label.textContent = name;
        const actions = document.createElement("span");
        actions.className = "place-actions";
        const go = document.createElement("button");
        go.className = "btn go-btn";
        go.textContent = "Go";
        go.setAttribute("aria-label", "Go to " + name);
        go.addEventListener("click", function () {
            window.panel.post("go", { name: name });
        });
        const see = document.createElement("button");
        see.className = "btn see-btn";
        see.textContent = "See";
        see.setAttribute("aria-label", "See " + name);
        see.addEventListener("click", function () {
            window.panel.post("see", { name: name });
        });
        const remove = document.createElement("button");
        remove.className = "btn remove-btn";
        remove.innerHTML = '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/></svg>';
        remove.title = "Remove " + name;
        remove.setAttribute("aria-label", "Remove " + name);
        remove.addEventListener("click", function () {
            window.panel.post("remove", { name: name });
        });
        actions.append(go, see, remove);
        row.append(label, actions);
        list.appendChild(row);
    }
}
window.panel.on("update", function (data) {
    allPlaces = Array.isArray(data.places) ? data.places : [];
    const status = document.getElementById("status");
    status.textContent = data.recording ? "Recording" : "Stopped";
    status.className = data.recording ? "recording" : "hint";
    start.disabled = data.recording;
    stop.disabled = !data.recording;
    renderPlaces();
});
search.addEventListener("input", renderPlaces);
document.getElementById("clear-search").addEventListener("click", function () {
    search.value = "";
    renderPlaces();
    search.focus();
});
start.addEventListener("click", function () { window.panel.post("start", {}); });
stop.addEventListener("click", function () { window.panel.post("stop", {}); });
window.panel.post("ready", {});
