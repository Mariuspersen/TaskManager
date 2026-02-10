async function main() {
  const showform_btn = document.getElementById("showtaskform_btn");
  const showname_btn = document.getElementById("shownameform_btn");
  const name_input = document.getElementById("name_input");
  const closeform_btn = document.getElementById("formCloseBtn");
  const namecloseform_btn = document.getElementById("nameformCloseBtn");
  closeform_btn.onclick = closeForm;
  namecloseform_btn.onclick = nameCloseForm;
  showform_btn.onclick = toggleForm;
  showname_btn.onclick = toggleNameForm;
  const name = window.localStorage.getItem("taskmanager_name")
  if(name) {
    name_input.value = name;
  }
  else {
    toggleNameForm();
  }
  await showlist();
}

async function nameCloseForm() {
  const showform_btn = document.getElementById("shownameform_btn");
  const name_form_div = document.getElementById("name_form");
  showform_btn.hidden = !showform_btn.hidden;
  name_form_div.style = "display: none";
}

async function closeForm() {
  const showform_btn = document.getElementById("showtaskform_btn");
  const task_form_div = document.getElementById("task-form");
  showform_btn.hidden = !showform_btn.hidden;
  task_form_div.style = "display: none";
}

async function toggleForm() {
  const showform_btn = document.getElementById("showtaskform_btn");
  const task_form_div = document.getElementById("task-form");
  showform_btn.hidden = !showform_btn.hidden;
  task_form_div.style = "display: flex";
}

async function toggleNameForm() {
  const shownameform_btn = document.getElementById("shownameform_btn");
  const name_form_div = document.getElementById("name_form");
  shownameform_btn.hidden = !shownameform_btn.hidden;
  name_form_div.style = "display: flex";
}

async function sendText(route, text) {
  const res = await fetch(route, {
    method: 'POST',
    body: text
  });
  return await res.text();
}

async function addTask(task, assignee) {
  await fetch("addtask", {
    method: 'POST',
    headers: { 'task': task, 'assignee': assignee },
  })
}

async function removeTask(task) {
  await fetch("removetask", {
    method: 'POST',
    headers: { 'task': task },
  })
}

async function changeName() {
  const showform_btn = document.getElementById("name_form");
  const name_input = document.getElementById("name_input");
  window.localStorage.setItem("taskmanager_name",name_input.value)
  location.reload();
}

async function addTaskButtonClicked() {
  const task_element = document.getElementById("task_input");
  const asignee_element = document.getElementById("assignee_input");
  await addTask(task_element.value, asignee_element.value);
  location.reload();
}

async function showlist() {
  const tasks = await sendText("listtasks", "");
  const tasklist_element = document.getElementById("tasklist");

  tasks.split(";").forEach(task => {
    if (task.length == 0) return;
    const split_task = task.split(":")
    const task_div = document.createElement('div');
    task_div.className = "task";

    const task_element = document.createElement('p');
    task_element.innerHTML += split_task[0];

    const asignee_element = document.createElement('p');
    asignee_element.innerHTML += "Assigned to: " + split_task[1];

    const finish_button = document.createElement('button');
    finish_button.innerText = "Finished";
    finish_button.className = "complete_button";
    finish_button.onclick = async () => {
      await removeTask(split_task[0]);
      location.reload();
    };
    const assign_button = document.createElement('button');
    assign_button.innerText = "Reassign to me";
    assign_button.className = "reassign_button";
    assign_button.onclick = async () => {
      await addTask(split_task[0],window.localStorage.getItem("taskmanager_name"))
      location.reload();
    }

    task_div.appendChild(task_element);
    task_div.appendChild(asignee_element);
    task_div.appendChild(finish_button);
    task_div.appendChild(assign_button);
    tasklist_element.appendChild(task_div);
  })
}

window.onload = main;