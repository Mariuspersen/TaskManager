# Simple Webserver for Assigning and Managing Tasks
meant to be used in a work environment where tasks can be assigned to people.
Entire server is designed to be dead simple with no bells nor whistles

I have been informed that this is basically scuffed trello

I consider this done in terms of features right now, excluding any bugs of course

## Some pictures

### Overview
What the user sees when opening the page, list of tasks, here you have the option to add a task, change name, and on each task you can mark them as finished, which will remove them from the list.
There is also a reassign button which you can reassign a existing task to someone else or yourself.
<img width="2434" height="1355" alt="image" src="https://github.com/user-attachments/assets/f0ef0760-3176-4fca-a2ba-307d429fc52a" />

### Adding a new task
Here is the menu for adding a task, simple text and assignee.
<img width="798" height="536" alt="image" src="https://github.com/user-attachments/assets/47bc2f96-2312-4f97-829b-b9045574fa6d" />

### Changing your name
On first opening the page, the user will be prompted for a name that will be saved in the webbrowser storage, used in the "Assign to me button in the reassign function"

<img width="701" height="295" alt="image" src="https://github.com/user-attachments/assets/b48bd6c2-f6cc-4886-95c5-0041aa906eb5" />

### Reassigning tasks
Here you can choose to assign it to some arbitrary name or yourself which you added in the "Change your name" feature
<img width="793" height="602" alt="image" src="https://github.com/user-attachments/assets/638d8a90-b184-46ac-8925-76951101c5b6" />

## Build and Run

### Prerequirements
- A Zig compiler 0.16.0-dev.2471+e9eadee00

NOTE: In build.zig.zon there is a couple of nobs you can tweak, which port, what the file should be called etc.

Open a terminal and do 
```
git clone https://github.com/Mariuspersen/TaskManager.git
cd TaskManager
zig build
zig-out/bin/task_manager
```
