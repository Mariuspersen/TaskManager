# Simple Webserver for Assigning and Managing Tasks
meant to be used in a work environment where tasks can be assigned to people.
Entire server is designed to be dead simple with no bells nor whistles

I have been informed that this is basically scuffed trello

I consider this done in terms of features right now, excluding any bugs of course

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
