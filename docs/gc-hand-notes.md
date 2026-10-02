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