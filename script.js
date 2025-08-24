// Training definitions
const paths = {
  handstand: [
    {
      name: "Level 1 — Wall Prep",
      blocks: [
        { name: "Warm-up", time: 180, img: "exercises/stretch.png" },
        { name: "Wall Hold", time: 300, img: "exercises/handstand-wall.png" },
        { name: "Pike Push-ups", time: 300, img: "exercises/pike-pushup.png" },
        { name: "Core Hollow Hold", time: 300, img: "exercises/hollow.png" },
        { name: "Cooldown", time: 180, img: "exercises/stretch.png" }
      ]
    },
    // Level 2, 3, 4, 5...
  ],
  arms: [
    {
      name: "Level 1 — Basics",
      blocks: [
        { name: "Push-ups", time: 120, img: "exercises/pushup.png" },
        { name: "Diamond Push-ups", time: 120, img: "exercises/diamond.png" },
        { name: "Chair Dips", time: 120, img: "exercises/dip.png" },
        { name: "Rest & Stretch", time: 120, img: "exercises/stretch.png" }
      ]
    },
    // Higher levels: archer pushups, pseudo planche pushups, handstand pushups...
  ],
  abs: [
    {
      name: "Level 1 — Core Start",
      blocks: [
        { name: "Plank", time: 60, img: "exercises/plank.png" },
        { name: "Leg Raises", time: 60, img: "exercises/legraise.png" },
        { name: "Hollow Hold", time: 60, img: "exercises/hollow.png" },
        { name: "Rest", time: 60, img: "exercises/stretch.png" }
      ]
    },
    // Higher levels: L-sit, dragon flag, hanging leg raise...
  ]
};

let state = JSON.parse(localStorage.getItem("workoutState")) || {
  currentPath: null,
  levelIndex: 0,
  history: []
};

let currentBlocks = [], currentBlock = 0, time = 0, interval = null;

function startPath(path) {
  state.currentPath = path;
  state.levelIndex = 0;
  save();
  loadLevel();
}

function loadLevel() {
  const path = paths[state.currentPath];
  const level = path[state.levelIndex];
  document.getElementById("training").style.display = "block";
  document.getElementById("pathTitle").textContent = state.currentPath.toUpperCase();
  document.getElementById("levelTitle").textContent = level.name;
  currentBlocks = level.blocks;
  currentBlock = 0;
  time = 0;
  renderBlock();
}

function renderBlock() {
  const block = currentBlocks[currentBlock];
  document.getElementById("exerciseText").textContent = block.name;
  document.getElementById("exerciseImg").src = block.img;
  document.getElementById("timer").textContent = `${block.time}s`;
}

function start() {
  if (interval) return;
  interval = setInterval(() => {
    time++;
    const block = currentBlocks[currentBlock];
    document.getElementById("timer").textContent = `${block.time - time}s`;
    if (time >= block.time) next();
  }, 1000);
}

function pause() {
  clearInterval(interval);
  interval = null;
}

function next() {
  pause();
  currentBlock++;
  time = 0;
  if (currentBlock >= currentBlocks.length) finish();
  else renderBlock();
}

function finish() {
  state.history.push(`${new Date().toLocaleString()} — Finished ${paths[state.currentPath][state.levelIndex].name}`);
  state.levelIndex = Math.min(state.levelIndex + 1, paths[state.currentPath].length - 1);
  save();
  loadLevel();
}

function save() {
  localStorage.setItem("workoutState", JSON.stringify(state));
}

document.getElementById("start").onclick = start;
document.getElementById("pause").onclick = pause;
document.getElementById("next").onclick = next;

document.getElementById("history").textContent = "History:\n" + state.history.join("\n");
