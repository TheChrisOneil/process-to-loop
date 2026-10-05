# See active sessions
tmux -L ptl-city ls

To attach to a live session:

tmux -L ptl-city attach -t <insert a session> 

Detach with Ctrl-B then d. Not Ctrl-C, which would interrupt the agent, and not closing the window.

Look without attaching
This is what I have been using, and it is safer:

tmux -L ptl-city capture-pane -p -t gc__run-operator-pc-kh3r | tail -30
Prints the pane's current contents and leaves. Add -S -100 to get more scrollback:

tmux -L ptl-city capture-pane -p -S -100 -t gc__run-operator-pc-kh3r


Check everything
cd ~/cities/ptl-city && gc status && gc session list && cd ~/cities/ptl-rig && gc bd list && gc bd ready
Narrower ones, which is usually what you want:

cd ~/cities/ptl-rig && gc bd list --status closed | grep -v 'Step spec'
cd ~/cities/ptl-rig && gc bd show <bead-id>
The close reason is the useful part — it's where each step says what it actually did.

Watch an agent without taking it over
tmux -L ptl-city capture-pane -p -S -200 -t gc__run-operator-pc-pgeg
Prints the last 200 lines and exits. It doesn't steal the terminal, so you can run it repeatedly or from a script. This is what I've been using.

Attach for real
tmux -L ptl-city attach -t gc__run-operator-pc-pgeg
Detach with ctrl-b then d. Leaving it attached is fine; killing the window is not.

The two live targets right now:

session	what it is
gc__run-operator-pc-pgeg	the worker — writes designs, runs gates
core__control-dispatcher-pc-7oyn	the controller — runs the checks
The dispatcher is the one worth watching for the current problem, since it's the process whose environment breaks the checks.

One thing that will bite you: plain tmux ls reads the default socket and will tell you no server is running while these are working a few inches away. Every city gets its own socket named after it, hence -L ptl-city.

List the socket's windows
tmux -L ptl-city ls