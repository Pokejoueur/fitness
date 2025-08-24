// Simple program definitions
const programs = {
  handstand: {
    name: "Handstand 30",
    levels: [
      {name: "Level 1: Prep", exercises:[
        {name:"Wrist Warmup", img:"img/wrist.svg", time:60},
        {name:"Plank Hold", img:"img/plank.svg", time:60},
        {name:"Wall Walk", img:"img/wallwalk.svg", time:60},
      ]},
      {name: "Level 2: Balance", exercises:[
        {name:"Crow Pose", img:"img/crow.svg", time:60},
        {name:"Wall Taps", img:"img/walltap.svg", time:60},
      ]}
    ]
  },
  arms: {
    name:"Full Arms Program",
    levels: [
      {name:"Level 1: Basics", exercises:[
        {name:"Push-ups", img:"img/pushup.svg", time:60},
        {name:"Diamond Push-ups", img:"img/diamond.svg", time:60},
      ]}
    ]
  },
  abs: {
    name:"Full Abs Program",
    levels: [
      {name:"Level 1: Core", exercises:[
        {name:"Crunches", img:"img/crunch.svg", time:60},
        {name:"Hollow Hold", img:"img/hollow.svg", time:60},
      ]}
    ]
  }
};

let currentProgram = null;
let currentLevel = 0;
let currentExercise = 0;
let timerInterval = null;
let timeLeft = 0;
let running = false;

// Load history
let history = JSON.parse(localStorage.getItem("history") || "[]");
renderHistory();

function startProgram(key){
  currentProgram = programs[key];
  currentLevel = 0;
  currentExercise = 0;
  document.getElementById("home").classList.add("hidden");
  document.getElementById("training").classList.remove("hidden");
  loadExercise();
}

function loadExercise(){
  const lvl = currentProgram.levels[currentLevel];
  const ex = lvl.exercises[currentExercise];
  document.getElementById("programName").innerText = currentProgram.name;
  document.getElementById("levelName").innerText = lvl.name;
  document.getElementById("exerciseText").innerText = ex.name;
  document.getElementById("exerciseImg").src = ex.img;
  timeLeft = ex.time;
  updateTimer();
}

function toggleTimer(){
  if(running){ pauseTimer(); }
  else { startTimer(); }
}

function startTimer(){
  if(timerInterval) clearInterval(timerInterval);
  running = true;
  timerInterval = setInterval(()=>{
    if(timeLeft>0){
      timeLeft--;
      updateTimer();
    } else {
      nextExercise();
    }
  },1000);
}

function pauseTimer(){
  running=false;
  clearInterval(timerInterval);
}

function updateTimer(){
  document.getElementById("timer").innerText = formatTime(timeLeft);
}

function formatTime(s){
  const m = Math.floor(s/60), sec = s%60;
  return `${m}:${sec.toString().padStart(2,"0")}`;
}

function nextExercise(){
  const lvl = currentProgram.levels[currentLevel];
  currentExercise++;
  if(currentExercise>=lvl.exercises.length){
    finishLevel();
  } else {
    loadExercise();
  }
}

function finishLevel(){
  history.push({date:new Date().toLocaleString(), program:currentProgram.name, level:currentProgram.levels[currentLevel].name});
  localStorage.setItem("history", JSON.stringify(history));
  renderHistory();
  currentExercise=0;
  currentLevel++;
  if(currentLevel>=currentProgram.levels.length){
    endWorkout();
  } else {
    loadExercise();
  }
}

function endWorkout(){
  pauseTimer();
  document.getElementById("home").classList.remove("hidden");
  document.getElementById("training").classList.add("hidden");
}

function renderHistory(){
  document.getElementById("history").innerText = history.map(h=>`${h.date} - ${h.program} (${h.level})`).join("\n");
}    },
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
