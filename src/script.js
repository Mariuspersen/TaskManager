const REFRESH_RATE = 10000;
async function main() {
  const showform_btn = document.getElementById("showtaskform_btn");
  const showname_btn = document.getElementById("shownameform_btn");
  const name_input = document.getElementById("name_input");
  const closeform_btn = document.getElementById("formCloseBtn");
  const cloe_reassign_form_btn = document.getElementById("assignformCloseBtn");
  const namecloseform_btn = document.getElementById("nameformCloseBtn");
  closeform_btn.onclick = closeForm;
  cloe_reassign_form_btn.onclick = assignformClose;
  namecloseform_btn.onclick = nameCloseForm;
  showform_btn.onclick = toggleForm;
  showname_btn.onclick = toggleNameForm;
  const name = window.localStorage.getItem("taskmanager_name")
  if (name) {
    name_input.value = name;
  }
  else {
    toggleNameForm();
  }
  await showlist();
  setInterval(showlist, REFRESH_RATE);
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

async function assignformClose() {
  const assign_to_form = document.getElementById("assign_to_form");
  assign_to_form.style = "display: none";
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
  }).then(r => {
    if (r.status >= 400 && r.status < 600) {
      showError("Server connection lost!")
    }
    return r;
  }).catch(e => showError(e));
  return await res.text();
}

async function addTask(task, assignee) {
  return await fetch("addtask", {
    method: 'POST',
    headers: { 'task': task, 'assignee': assignee },
  }).then(r => {
    if (r.status == 406) {
      r.text().then(t => {
        showError(t)
      })
    }
    return r;
  }).catch(e => showError(e));
}

async function removeTask(task) {
  return await fetch("removetask", {
    method: 'POST',
    headers: { 'task': task },
  })
}

async function changeName() {
  const showform_btn = document.getElementById("name_form");
  const name_input = document.getElementById("name_input");
  window.localStorage.setItem("taskmanager_name", name_input.value)
  await nameCloseForm();
}

async function addTaskButtonClicked() {
  const task_element = document.getElementById("task_input");
  const asignee_element = document.getElementById("assignee_input");
  await addTask(task_element.value, asignee_element.value);
  await showlist()
  await closeForm()
}

async function showError(e) {
  const ERROR_NAME = "error_popup";
  const show_error = document.createElement('p');
  show_error.className = ERROR_NAME;
  show_error.id = ERROR_NAME;
  show_error.innerText = e;
  setTimeout(() => {
    const e = document.getElementById(ERROR_NAME);
    const body = document.getElementById("body");
    body.removeChild(e);

  }, REFRESH_RATE)

  const body = document.getElementById("body");
  body.appendChild(show_error);
}

async function showlist() {
  const tasks = await sendText("listtasks", "")

  const old_tasklist_element = document.getElementById("tasklist");
  if(tasks.length == 0) {
    old_tasklist_element.innerHTML = "";
  }
  
  const new_tasklist_element = document.createElement("div");

  new_tasklist_element.id = old_tasklist_element.id;

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
      await showlist()
    };
    const assign_to_button = document.createElement('button');
    assign_to_button.innerText = "Reassign";
    assign_to_button.className = "reassign_to_button";
    assign_to_button.onclick = async () => {
      const assign_to_form = document.getElementById("assign_to_form")
      const assign_to_confirm_btn = document.getElementById("assign_form_btn");
      const assign_to_me_btn = document.getElementById("assign_to_me_btn");
      assign_to_form.style = "display: flex";

      assign_to_me_btn.onclick = async () => {
        await addTask(split_task[0], window.localStorage.getItem("taskmanager_name"));
        const assign_to_form = document.getElementById("assign_to_form")
        assign_to_form.style = "display: none";
        await showlist();
      }
      
      assign_to_confirm_btn.onclick = async () => {
        const assignment_name_input = document.getElementById("assignment_name_input");
        await addTask(split_task[0], assignment_name_input.value);
        const assign_to_form = document.getElementById("assign_to_form")
        assign_to_form.style = "display: none";
        await showlist();
      };

    }

    const button_container = document.createElement("div");
    button_container.className = "button_container";
    button_container.appendChild(finish_button);
    button_container.appendChild(assign_to_button);

    task_div.appendChild(task_element);
    task_div.appendChild(asignee_element);
    task_div.appendChild(button_container);
    new_tasklist_element.appendChild(task_div);

    old_tasklist_element.replaceWith(new_tasklist_element);
  })
}

window.onload = main;