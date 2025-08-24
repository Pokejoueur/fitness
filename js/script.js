document.addEventListener('DOMContentLoaded', () => {
  // Load workout data
  fetch('data/workouts.json')
    .then(response => response.json())
    .then(data => initializeApp(data))
    .catch(error => console.error('Error loading workouts:', error));

  function initializeApp(workouts) {
    const workoutSelection = document.querySelector('.workout-selection');
    const workoutArea = document.querySelector('.workout-area');
    const workoutTitle = document.getElementById('workout-title');
    const levelSelection = document.getElementById('level-selection');
    const exerciseImage = document.getElementById('exercise-image');
    const exerciseName = document.getElementById('exercise-name');
    const timerDisplay = document.getElementById('timer');
    const startBtn = document.getElementById('start-btn');
    const pauseBtn = document.getElementById('pause-btn');
    const nextBtn = document.getElementById('next-btn');
    const backBtn = document.getElementById('back-btn');

    let currentWorkout = null;
    let currentLevel = 0;
    let currentExercise = 0;
    let timer = null;
    let timeLeft = 0;
    let isPaused = false;

    // Load progress from localStorage
    let progress = JSON.parse(localStorage.getItem('progress')) || {
      handstand: [true], // First level unlocked by default
      abs: [true],
      arms: [true]
    };

    // Workout selection
    workoutSelection.addEventListener('click', (e) => {
      if (e.target.classList.contains('workout-btn')) {
        currentWorkout = e.target.dataset.type;
        workoutTitle.textContent = workouts[currentWorkout].name;
        renderLevels();
        workoutSelection.style.display = 'none';
        workoutArea.style.display = 'block';
      }
    });

    // Level selection
    levelSelection.addEventListener('click', (e) => {
      if (e.target.classList.contains('level-btn')) {
        currentLevel = parseInt(e.target.dataset.level);
        currentExercise = 0;
        renderExercise();
      }
    });

    // Start button
    startBtn.addEventListener('click', () => {
      startBtn.disabled = true;
      pauseBtn.disabled = false;
      nextBtn.disabled = false;
      isPaused = false;
      startTimer();
    });

    // Pause button
    pauseBtn.addEventListener('click', () => {
      isPaused = !isPaused;
      pauseBtn.textContent = isPaused ? 'Resume' : 'Pause';
      if (!isPaused) startTimer();
      else clearInterval(timer);
    });

    // Next button
    nextBtn.addEventListener('click', () => {
      currentExercise++;
      if (currentExercise < workouts[currentWorkout].levels[currentLevel].exercises.length) {
        clearInterval(timer);
        startBtn.disabled = false;
        pauseBtn.disabled = true;
        nextBtn.disabled = true;
        isPaused = false;
        pauseBtn.textContent = 'Pause';
        renderExercise();
      } else {
        // Level completed
        clearInterval(timer);
        unlockNextLevel();
        workoutSelection.style.display = 'block';
        workoutArea.style.display = 'none';
      }
    });

    // Back button
    backBtn.addEventListener('click', () => {
      clearInterval(timer);
      workoutSelection.style.display = 'block';
      workoutArea.style.display = 'none';
      startBtn.disabled = false;
      pauseBtn.disabled = true;
      nextBtn.disabled = true;
      isPaused = false;
      pauseBtn.textContent = 'Pause';
    });

    function renderLevels() {
      levelSelection.innerHTML = '';
      workouts[currentWorkout].levels.forEach((level, index) => {
        const button = document.createElement('button');
        button.classList.add('level-btn');
        button.textContent = `Level ${index + 1}`;
        button.dataset.level = index;
        button.disabled = !progress[currentWorkout][index];
        levelSelection.appendChild(button);
      });
    }

    function renderExercise() {
      const exercise = workouts[currentWorkout].levels[currentLevel].exercises[currentExercise];
      exerciseName.textContent = exercise.name;
      exerciseImage.src = exercise.image;
      timeLeft = exercise.duration;
      timerDisplay.textContent = formatTime(timeLeft);
    }

    function startTimer() {
      clearInterval(timer);
      timer = setInterval(() => {
        if (!isPaused) {
          timeLeft--;
          timerDisplay.textContent = formatTime(timeLeft);
          if (timeLeft <= 0) {
            clearInterval(timer);
            nextBtn.click();
          }
        }
      }, 1000);
    }

    function formatTime(seconds) {
      const mins = Math.floor(seconds / 60).toString().padStart(2, '0');
      const secs = (seconds % 60).toString().padStart(2, '0');
      return `${mins}:${secs}`;
    }

    function unlockNextLevel() {
      if (!progress[currentWorkout][currentLevel + 1]) {
        progress[currentWorkout][currentLevel + 1] = true;
        localStorage.setItem('progress', JSON.stringify(progress));
      }
    }
  }
});let currentProgram = null;
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
