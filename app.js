// === Data ===
const exercises = [
  {id:1,name:"Push Ups",muscles:"Chest, Triceps",difficulty:1,preview:"https://www.youtube.com/embed/IODxDxX7oi4"},
  {id:2,name:"Handstand",muscles:"Shoulders, Core",difficulty:3,preview:"https://www.youtube.com/embed/0G9b9q1r9Bs"},
  {id:3,name:"Squats",muscles:"Legs",difficulty:1,preview:"https://www.youtube.com/embed/aclHkVaku9U"}
];

const programs = [
  {id:1,name:"Full Body Beginner",exercises:[1,3]},
  {id:2,name:"Handstand Prep",exercises:[2,1]}
];

// === State ===
let currentUser = null;
let currentWorkout = [];
let currentExerciseIndex = 0;

// === Elements ===
const loginSection = document.getElementById('login-section');
const dashboardSection = document.getElementById('dashboard-section');
const workoutSection = document.getElementById('workout-section');
const userNameEl = document.getElementById('user-name');
const exerciseContainer = document.getElementById('exercise-container');

// === Login ===
document.getElementById('login-btn').onclick = () => {
  const name = document.getElementById('username').value.trim();
  if(!name) return alert("Enter a name");
  currentUser = {name, workouts:[], skillLogs:[]};
  localStorage.setItem('user', JSON.stringify(currentUser));
  loginSection.classList.add('hidden');
  dashboardSection.classList.remove('hidden');
  userNameEl.textContent = currentUser.name;
};

// === Start Workout ===
document.getElementById('start-workout').onclick = () => {
  currentWorkout = programs[0].exercises.map(id => exercises.find(e => e.id===id));
  currentExerciseIndex = 0;
  dashboardSection.classList.add('hidden');
  workoutSection.classList.remove('hidden');
  showExercise();
};

// === Show Exercise ===
function showExercise() {
  const ex = currentWorkout[currentExerciseIndex];
  exerciseContainer.innerHTML = `
    <h3>${ex.name}</h3>
    <p>Muscles: ${ex.muscles}</p>
    <iframe width="300" height="170" src="${ex.preview}" frameborder="0" allowfullscreen></iframe>
  `;
}

// === Next Exercise ===
document.getElementById('next-exercise').onclick = () => {
  currentExerciseIndex++;
  if(currentExerciseIndex >= currentWorkout.length) {
    alert("Workout Complete!");
    workoutSection.classList.add('hidden');
    dashboardSection.classList.remove('hidden');
    currentUser.workouts.push({date:new Date().toLocaleString(), program:programs[0].name});
    localStorage.setItem('user', JSON.stringify(currentUser));
    return;
  }
  showExercise();
};

// === End Workout ===
document.getElementById('end-workout').onclick = () => {
  workoutSection.classList.add('hidden');
  dashboardSection.classList.remove('hidden');
};
