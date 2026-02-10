
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

async function main() {
  const showform_btn = document.getElementById("showtaskform_btn");
  const closeform_btn = document.getElementById("formCloseBtn");
  closeform_btn.onclick = closeForm;
  showform_btn.onclick = toggleForm;
  await showlist();
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
    finish_button.onclick = async () => {
      await removeTask(split_task[0]);
      location.reload();
    };

    task_div.appendChild(task_element);
    task_div.appendChild(asignee_element);
    task_div.appendChild(finish_button);
    tasklist_element.appendChild(task_div);
  })
}

window.onload = main;